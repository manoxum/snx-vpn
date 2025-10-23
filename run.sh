cd "$(dirname "$(readlink -f "$0")")"

docker rm -f inic-vpn
docker build -t inic-vpn .
sleep 3
docker logs inic-vpn
docker exec -it inic-vpn bash

