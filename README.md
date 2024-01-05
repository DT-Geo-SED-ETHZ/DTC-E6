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

## Setup aliases

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

## Update inventory
```bash

# Metadata INGV (Z3 removed)
curl http://webservices.ingv.it/fdsnws/station/1/query"?format=xml&level=response" > webservices.ingv.it.xml 
/opt/seiscomp/bin/seiscomp exec fdsnxml2inv webservices.ingv.it.xml > webservices.ingv.it.scml   
/opt/seiscomp/bin/seiscomp exec invextr --rm --chans "Z3.*" webservices.ingv.it.scml > webservices.ingv.it.filt.scml
 
# Metadata SED (GU removed)
/opt/seiscomp/bin/seiscomp exec scxmldump -d "postgresql://seiscomp3:birkidollar5s@eq20d.ethz.ch:5432/sc3dbd?column_prefix=m_"  --plugins dbpostgresql -I > arclink.ethz.ch.scml
/opt/seiscomp/bin/seiscomp exec invextr --rm --chans "GU.*" arclink.ethz.ch.scml >  arclink.ethz.ch.filt.scml

# Merging SEd and INGV
scinv merge arclink.ethz.ch.filt.scml webservices.ingv.it.filt.scml -o /opt/seiscomp/etc/inventory/arclink.ethz.ch.noGU-merged-webservices.ingv.it.noZ3.xml
 
# Update seiscomp
seiscomp update-config

# Find missing channels (assuming to day is 2024/01/05)
slinktool -Q dt-geo-seedlink.ethz.ch:18000 |grep 2024/01/05|sed 's/    /  _  /'|while read N S L C T;do curl http://localhost:8080/fdsnws/station/1/query"?network=$N&station=$S&location=${L/_/}&channel=$C&level=channel" 2>/dev/null |grep $S >/dev/null|| echo missing $N $S $L $C;done #|awk '{print $2"."$3}'|sort -u
```

On 2024/01/05, the following are still missing:
```bash
missing IV MALA5 _ EHE
missing IV MALA5 _ EHN
missing IV MALA5 _ EHZ
missing IV MALA2 _ EHE
missing IV MALA2 _ EHN
missing IV MALA2 _ EHZ
missing IV MALA4 _ EHE
missing IV MALA4 _ EHN
missing IV MALA4 _ EHZ
missing IV MALA0 _ EHE
missing IV MALA0 _ EHN
missing IV MALA0 _ EHZ
missing IV MALA3 _ EHE
missing IV MALA3 _ EHN
missing IV MALA3 _ EHZ
```
