#!/bin/bash



usr='caIixo'


echo "[INFO] Creating user '$usr'..."
uid=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
uid=$((uid + 1))
echo "[INFO] Using UID: $uid"
read -s -p "Enter password for new user: " password
echo ""
read -s -p "Confirm password: " password2
echo ""
if [ "$password" != "$password2" ]; then
    echo "[ERROR] Passwords do not match. Exiting."
    exit 1
fi
echo "[INFO] Passwords match."

sudo dscl . -create /Users/$usr
sudo dscl . -create /Users/$usr UserShell /bin/zsh
sudo dscl . -create /Users/$usr UniqueID $uid
sudo dscl . -create /Users/$usr PrimaryGroupID 20
sudo dscl . -create /Users/$usr NFSHomeDirectory /Users/$usr
sudo dscl . -passwd /Users/$usr "$password"

sudo mkdir -p /Users/$usr
sudo chown -R $uid:20 /Users/$usr

 
echo "[INFO] Done. User '$usr' is ready."

exec su - $usr 
