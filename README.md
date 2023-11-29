# FinDer, scfinder and FinDer-in-a-Docker config for DT-Geo

## Get FinDer-in-a-Docker (assuming granted access)

```bash
docker login ghcr.io/sed-eew/finder
docker pull  ghcr.io/sed-eew/finder 
```

## Update existing container (re-use same docker volume for permanent logs)

```bash
# RUN ONLY IF REALLY NEEDED
# docker stop finder && docker rm finder && docker run -d --add-host=host.docker.internal:host-gateway -p 9878:22 -v finder:/home/sysop --hostname FinDer-in-a-Docker --name finder ghcr.io/sed-eew/finder:master
```

## Make aliases

```bash
docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp alias create scfdalpine scfinder
docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp alias create scfditaly  scfinder
docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp alias create scfdforela scfinder

docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp enable scfdalpine scfditaly scfdforela 
```

## Update SeisComP and FinDer config

```bash
docker cp /opt/seiscomp/etc/FinDer-config/ finder:/opt/seiscomp/etc/FinDer-config/

docker cp /opt/seiscomp/etc/global.cfg     finder:/opt/seiscomp/etc/
docker cp /opt/seiscomp/etc/scfdforela.cfg finder:/opt/seiscomp/etc/
docker cp /opt/seiscomp/etc/scfdalpine.cfg finder:/opt/seiscomp/etc/
docker cp /opt/seiscomp/etc/scfditaly.cfg  finder:/opt/seiscomp/etc/

docker cp /opt/seiscomp/etc/global.FinDer-in-a-Docker.cfg  finder:/home/sysop/.seiscomp/global.cfg

docker exec -u 0 -it finder chown sysop:sysop /opt/seiscomp -R
docker exec -u 0 -it finder chown sysop:sysop /home/sysop/.seiscomp/global.cfg
```

## Restart scfinder aliases in container
```bash
docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp restart
```
