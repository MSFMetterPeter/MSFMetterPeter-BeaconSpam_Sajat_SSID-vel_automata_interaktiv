#!/bin/bash
# Színek
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
#Ascii art source: https://ascii.co.uk/art/beacon
echo -e "${RED}"
cat << 'EOF'
 _                                
| |                               
| |__   ___  __ _  ___ ___  _ __  
| '_ \ / _ \/ _` |/ __/ _ \| '_ \ 
| |_) |  __/ (_| | (_| (_) | | | |
|_.__/ \___|\__,_|\___\___/|_| |_|

EOF

echo -e "${GREEN}========================="
echo -e "I  ${NC}Beacon Spam Script${GREEN}   I"
echo -e "========================="
echo -e "${RED}Author:${NC} MSF Metter Peter"

# Online hálózati interfészek listázása és kiválasztása
echo "Elérhető online interfészek:"
echo "-----------------------------"

# Csak az UP állapotú interfészek listázása (index nélkül)
mapfile -t interfaces < <(ip link show up | awk -F': ' '/^[0-9]+:/{print $2}' | grep -v lo)

if [ ${#interfaces[@]} -eq 0 ]; then
    echo "Nem található online interfész."
    exit 1
fi

# Sorszámozott lista megjelenítése
for i in "${!interfaces[@]}"; do
    echo "  [$((i+1))] ${interfaces[$i]}"
done

echo ""
read -rp "Válassz interfészt (1-${#interfaces[@]}): " choice

# Ellenőrzés
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#interfaces[@]}" ]; then
    echo "Érvénytelen választás."
    exit 1
fi

selected="${interfaces[$((choice-1))]}"
echo ""
echo "Kiválasztott interfész: $selected"
echo "Monitor mód inditása ezen az interfészen:$selected"
echo ""

sudo airmon-ng check kill
sudo airmon-ng start "$selected"

echo -e "Beacon Spam Script inditása"

if [[ $EUID -ne 0 ]]; then
  echo "Root jogosultság szükséges! Futtasd: sudo $0"
  exit 1
fi

# Interfész lista
echo "=== Elérhető WiFi interfészek ==="
iw dev | grep Interface | awk '{print $2}'
echo ""

read -p "Interfész neve (pl. wlan1): " INTERFACE
read -p "Alap SSID neve (pl. HomeRouter): " BASE_SSID

# Darabszám választás
echo ""
echo "=== Hány SSID-t generáljon? ==="
echo "  1) 50"
echo "  2) 100"
echo "  3) 500"
echo "  4) 1000"
echo "  5) Egyedi szám"
read -p "Válassz (1-5): " COUNT_CHOICE

case $COUNT_CHOICE in
  1) COUNT=50 ;;
  2) COUNT=100 ;;
  3) COUNT=500 ;;
  4) COUNT=1000 ;;
  5) read -p "Add meg a számot: " COUNT ;;
  *) echo "Érvénytelen választás, alapértelmezett: 100"; COUNT=100 ;;
esac

# Sebesség választás
echo ""
echo "=== Sebesség (beacon/s) ==="
echo "  1) 100  (lassú)"
echo "  2) 300  (közepes)"
echo "  3) 500  (gyors)"
echo "  4) Egyedi"
read -p "Válassz (1-4): " SPEED_CHOICE

case $SPEED_CHOICE in
  1) SPEED=100 ;;
  2) SPEED=300 ;;
  3) SPEED=500 ;;
  4) read -p "Add meg a sebességet: " SPEED ;;
  *) echo "Érvénytelen választás, alapértelmezett: 200"; SPEED=200 ;;
esac

WORDLIST="/tmp/ssid_list.txt"

# Összefoglaló
echo ""
echo "================================"
echo "  Interfész : $INTERFACE"
echo "  Alap SSID : $BASE_SSID"
echo "  Darabszám : $COUNT"
echo "  Sebesség  : $SPEED beacon/s"
echo "================================"
read -p "Indítás? (i/n): " CONFIRM
if [[ "$CONFIRM" != "i" ]]; then
  echo "Megszakítva."
  exit 0
fi

# SSID generálás
echo ""
echo "[*] SSID-k generálása..."
> "$WORDLIST"
for i in $(seq 1 $COUNT); do
  printf "%s_%04d\n" "$BASE_SSID" "$i" >> "$WORDLIST"
done
echo "[*] $(wc -l < $WORDLIST) SSID generálva."

# NetworkManager leállítása
echo "[*] NetworkManager leállítása..."
systemctl stop NetworkManager
sleep 1

# Monitor mód bekapcsolása
echo "[*] Monitor mód bekapcsolása: $INTERFACE"
ip link set "$INTERFACE" down
iw dev "$INTERFACE" set type monitor
ip link set "$INTERFACE" up
echo "[*] Monitor mód aktív."

# Cleanup - Ctrl+C vagy hiba esetén
cleanup() {
  echo ""
  echo "[*] Leállítás..."

  # Monitor mód leállítása (airmon-ng által létrehozott interfész)
  MON_IF="${selected}mon"
  if ip link show "$MON_IF" &>/dev/null; then
    echo "[*] Monitor mód leállítása: $MON_IF"
    airmon-ng stop "$MON_IF"
    echo "[*] Monitor mód leállítva."
  fi

  # Interfész visszaállítása managed módba (ha még létezik)
  if ip link show "$INTERFACE" &>/dev/null; then
    echo "[*] Interfész visszaállítása managed módra: $INTERFACE"
    ip link set "$INTERFACE" down
    iw dev "$INTERFACE" set type managed
    ip link set "$INTERFACE" up
    echo "[*] Managed mód visszaállítva."
  fi

  # NetworkManager újraindítása
  echo "[*] NetworkManager újraindítása..."
  systemctl start NetworkManager
  sleep 2

  # Ellenőrzés
  if systemctl is-active --quiet NetworkManager; then
    echo "[*] NetworkManager elindult."
  else
    echo "[!] NetworkManager nem indult el, kézi indítás: sudo systemctl start NetworkManager"
  fi

  rm -f "$WORDLIST"
  echo "[*] Kész."
  exit 0
}
trap cleanup INT TERM EXIT

# Beacon spam indítása
echo "[*] Beacon spam indul! (Ctrl+C = leállítás)"
echo ""
mdk4 "$INTERFACE" b -f "$WORDLIST" -s "$SPEED"

cleanup
