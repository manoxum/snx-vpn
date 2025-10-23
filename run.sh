cd "$(dirname "$(readlink -f "$0")")"

docker rm -f inic-vpn
docker build -t inic-vpn .
docker run --rm -it \
  --privileged \
  --cap-add=NET_ADMIN \
  -p 2222:22 \
  -d  \
  -v /lib/modules:/lib/modules:ro \
  --device /dev/net/tun \
  --env-file .env.local \
  --name inic-vpn \
  inic-vpn:latest

sleep 3
docker logs inic-vpn
docker exec -it inic-vpn bash

