# Authelia JWT
echo "[Authelia JWT]"
docker run --rm authelia/authelia:latest authelia crypto rand --length 32
# Authelia session secret
echo "[Authelia session]"
docker run --rm authelia/authelia:latest authelia crypto rand --length 32
# Authelia storage secret
echo "[Authelia storage]"
docker run --rm authelia/authelia:latest authelia crypto rand --length 32
# Authelia user password
echo "[Authelia credentials]"
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'admin'