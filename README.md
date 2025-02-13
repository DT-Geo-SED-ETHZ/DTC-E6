# FinDer, scfinder and FinDer-in-a-Docker config for DT-Geo

## Build and run a standalone FinDer docker for DT-Geo

```
docker build -f "Dockerfile" -t dtgeofinder:master "."

docker stop dtgeofinder 

docker rm dtgeofinder 

docker run -d \
    -p 9878:22 \
    -v dtgeofinder:/home/sysop \
    --hostname FinDer-for-DTGeo-Docker \
    --name dtgeofinder \
    dtgeofinder:master
```

## Interactive shell - shakemap test
```bash
docker exec -it dtgeofinder bash
cd shakemap

sm_create ci3144585 -e ci 1994-01-17T12:30:55 -118.546 34.211 19 6.6 "Northridge, California" -n
shake ci3144585 select
shake ci3144585 assemble
```

## Connection to ADACloud @ CINECA for DT-GEO execution of workflow
If you do not already have it create an account at userdb.hpc.cineca.it and write mail to johannes.kemper@eaps.ethz.ch.
Login to the ADACloud (adacloud.hpc.cineca.it) and start the respective virtual machine (VM) called DTC-E6.
Connect via ssh to this machine (IP address is in the ADACloud dashboard - currently 131.175.206.100) with standard user "ubuntu".
```bash
ssh ubuntu@131.175.206.100
```
Docker should be installed and ready to use and you can git clone this repository and start building. 

## Blacklist HH with colocated HN
```bash
NOW=$( date +%s )
function date2s () {  date --date="$1 UTC"  +%s ;} 

for U in dt-geo-seedlink.ethz.ch:18000 eq20b.ethz.ch:18000 ;
do 
  slinktool -Q $U ;
done|sed 's/    / __ /'|while read N S L C Q D1 T1 T D2 T2; 
do 
   DELAY=$(( $NOW -  $( date2s "$D2 $T2" ))); 
   if [[ $DELAY -lt 1000 ]] ; 
   then 
    echo  $N $S $L $C $Q $D1 $T1 $T $D2 $T2 $DELAY ;
   fi ;
done > slinktool_with_delay.log
grep -i -e " HNZ " -e " HGZ "  slinktool_with_delay.log |while read N S L T ;do grep "^$N $S .* HHZ " slinktool_with_delay.log >/dev/null&& echo "$N.$S.*.HH*";done|paste -s -d ',' -
```

## Miniseed-based real-time simulation

Alias the msrtsimul docker command (once per session):
```bash


msrtsimuld () { 
  docker exec -u sysop     msrtsimuld sh -c 'rm /home/sysop/seiscomp/etc/inventory/*.xml'
  docker exec -u sysop -it finder     sed -i 's/^#recordstream = slink:\/\/host.docker.internal:18000/recordstream = slink:\/\/host.docker.internal:18000/' /home/sysop/.seiscomp/global.cfg
  docker exec -u sysop -it finder     /opt/seiscomp/bin/seiscomp restart scfditaly scfdforela  scfdalpine
  docker exec -u 0     -it msrtsimuld main $@ ; 
  docker exec -u sysop -it finder     sed -i 's/^recordstream = slink:\/\/host.docker.internal:18000/#recordstream = slink:\/\/host.docker.internal:18000/' /home/sysop/.seiscomp/global.cfg
  docker exec -u sysop -it finder     /opt/seiscomp/bin/seiscomp restart scfditaly scfdforela  scfdalpine
  }           

msrtsimuld () { 
  docker exec -u sysop     msrtsimuld sh -c 'rm /home/sysop/seiscomp/etc/inventory/*.xml'
  docker exec -u sysop -it finder     sed -i 's/^#recordstream = slink:\/\/host.docker.internal:18000/recordstream = slink:\/\/host.docker.internal:18000/' /home/sysop/.seiscomp/global.cfg
  docker exec -u sysop -it finder     /opt/seiscomp/bin/seiscomp restart scfditaly 
  docker exec -u 0     -it msrtsimuld main $@ ; 
  docker exec -u sysop -it finder     sed -i 's/^recordstream = slink:\/\/host.docker.internal:18000/#recordstream = slink:\/\/host.docker.internal:18000/' /home/sysop/.seiscomp/global.cfg
  docker exec -u sysop -it finder     /opt/seiscomp/bin/seiscomp restart scfditaly 
  } 
```

Run any of the simulations:
```bash
msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2009-04-06T01-32-40.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2009-04-06T01-32-40.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2012-05-20T02-03-50.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2012-05-20T02-03-50.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2012-05-29T07-00-02.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2012-05-29T07-00-02.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-08-24T01-36-32.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-08-24T01-36-32.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-10-26T19-18-07.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-10-26T19-18-07.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-10-30T06-40-17.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2016-10-30T06-40-17.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2017-01-18T10-14-09.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2017-01-18T10-14-09.xml,sc3

msrtsimuld \
  sysop@host.docker.internal:/home/sysop/playback/test1/2022-11-09T06-07-25.mseed \
  sysop@host.docker.internal:/home/sysop/playback/test1/2022-11-09T06-07-25.xml,sc3
```

See the produced event(s) with simulated data access:
```bash
scolv -I slink://localhost:18000
```

Consider setting simulated events as "Not existing"

## Playback

Disable all scfinder aliases:
```bash
docker exec -u sysop  -it scpbd /opt/seiscomp/bin/seiscomp disable scfdalpine scfdforela scfditaly
```

Enable the appropriate alias:
```bash
docker exec -u sysop  -it scpbd /opt/seiscomp/bin/seiscomp enable scfditaly
```

Adjust the configuration:
```bash
ssh -X -p 222 sysop@localhost /opt/seiscomp/bin/seiscomp exec scconfig
```

Playback mseed data "playback/test1/2016-10-30T06-40-17.mseed512"  with metadata inventory "playback/test1/inv.xml" in format "sc3":
```bash
docker exec -u 0 -it scpbd main $USER@host.docker.internal:$(pwd)/playback/test1/2016-10-30T06-40-17.mseed512 $USER@host.docker.internal:$(pwd)/playback/test1/2016-10-30T06-40-17.xml,sc3 
```

Save the results:
```bash
docker cp scpbd:/home/sysop/event_db.sqlite playback/test1/2016-10-30T06-40-17.sqlite
```

More info: https://github.com/FMassin/scpbd


## Get FinDer-in-a-Docker (assuming granted access)

```bash
docker login ghcr.io/sed-eew/finder
docker pull  ghcr.io/sed-eew/finder:master 
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
docker cp  finder:/home/sysop/.seiscomp/FinDer-config/ /home/sysop/.seiscomp/FinDer-config/
docker cp  finder:/home/sysop/.seiscomp/scfd*.cfg /home/sysop/.seiscomp/

# UPDATE CONFIG IN /home/sysop/.seiscomp/ AND THEN:

docker cp /home/sysop/.seiscomp/FinDer-config/ finder:/home/sysop/.seiscomp/FinDer-config/

docker cp /home/sysop/.seiscomp/scfdforela.cfg finder:/home/sysop/.seiscomp/
docker cp /home/sysop/.seiscomp/scfdalpine.cfg finder:/home/sysop/.seiscomp/
docker cp /home/sysop/.seiscomp/scfditaly.cfg  finder:/home/sysop/.seiscomp/

docker exec -u 0 -it finder chown sysop:sysop /home/sysop/.seiscomp/ -R
```

## Restart scfinder aliases in container

```bash
docker exec -u sysop -it finder /opt/seiscomp/bin/seiscomp restart scfdalpine scfditaly scfdforela
```
Ignore or stop scmaster in the docker container.

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
