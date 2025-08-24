#!/usr/bin/env python3

import re
import math
import time
import os
import shutil
import glob
import string
import optparse
import datetime

###########################################################################################
# Classes:
#------------------------------------------------------------------------------------------
class bindings(object):

      def __init__(self,keyfi,net,sta,alink,alinkacs,globalprofile,scautopickprofile,pipelines):
          self.keyfi = str(keyfi)
          self.net   = str(net)
          self.sta   = str(sta)
          self.alink = str(alink)
          self.alinkacs = str(alinkacs)
          self.globalprofile = str(globalprofile)
          self.scautopickprofile = str(scautopickprofile)
          self.pipelines = pipelines

      def __str__(self):
           return '%-20s %-5s %-7s %-20s %-20s %-20s %-20s' % (self.keyfi,self.net,self.sta,self.alink,self.alinkacs,self.globalprofile,self.scautopickprofile)
#------------------------------------------------------------------------------------------
class plines(object):

      def __init__(self,module,profile):

          self.module = str(module)
          self.profile = str(profile)

###########################################################################################
#Subroutines/functions:

#------------------------------------------------------------------------------------------
def str2bool(string):
    return string.lower() in ("yes", "true", "t", "1")
#------------------------------------------------------------------------------------------
def loadbindings(ifile,modulelist):
    list = []
    mullist = []

    #Open
    fp = open(ifile,"r")

    for line in fp:

        t = line.split(None,-1)

        #Check if line is empty:
        if(len(t)==0):
           continue

        if(t[0].startswith("#") == False):

           #Check if format is sufficient:
           if(len(t)<7):
               print("Missing information: Skip line -",line)
               continue   

           plist = []

           #Check if station is already included:
           bnew = True
           for l in range(len(list)):
               if( list[l].keyfi.strip() == t[0].strip() ):
                  print( "WARNING: Multiple Definition For Keyfile",t[0])
                  mullist.append(t[0])

           #Check for additional pipeline definition:
           p = line.split("ADD2PIPELINE",-1)

           if(len(p)-1 > 0):
              for k in range(len(p)-1):
                  e = p[k+1].split(None,-1)
                  module = e[0]
                  profil = e[1]

                  #Check if module is new:
                  mnew = True
                  for n in range(len(modulelist)):
                      if(module == modulelist[n]):
                         mnew = False
                         break

                  #Module new:
                  if(mnew):
                     print("Add new module:",module)
                     modulelist.append(module)


                  #print "Additional pipeline",k,e[0],e[1]
                  plist.append(plines(e[0],e[1]))

           list.append(bindings(t[0],t[1],t[2],t[3],t[4],t[5],t[6],plist))
           #print bindings(t[0],t[1],t[2],t[3],t[4],t[5],t[6],plist)

    fp.close()

    return list,modulelist,mullist
#------------------------------------------------------------------------------------------
###########################################################################################
# Main:

# File which contains binding definitions:
bindingfile = "/home/sysop/svn/stations/SC3_MasterStationList.txt"

# Setup directory to backup all existing station-key files:
nowt = datetime.datetime.now()
backupdir = "keyfile-backup" + "-" + str(nowt.date()) + "_" + str(nowt.hour) + "-" + str(nowt.minute) + "-" + str(nowt.second)

#Check if backup-directory exists, if not create:
if((os.path.isdir(backupdir)) is False):
    #print "mkdir",backupdir
    os.makedirs(backupdir)

#List with picker modules to check (modules listed in "bindingfile" not included here will be appended:
#picker2check = ["NLoB_apick","NTeT_apick"]
picker2check = []

#Get a list of existing key files:
oldkey = glob.glob("station_*_*")
#print oldkey

#Backup old files:
print("Backup old keyfiles in current directory to",backupdir)
for i in range(len(oldkey)):
    shutil.copy2(oldkey[i], backupdir)

#Load binding definitions:
print("")
print("Load bindings from",bindingfile)
defbind,picker2check,multidef = loadbindings(bindingfile,picker2check)

print("")
print("Write new station-keyfiles")

for i in range(len(defbind)):

    #Check if keyfile already exists:
    knew = True
    for j in range(len(oldkey)):
        if(defbind[i].keyfi == oldkey[j]):
           knew = False
           break
 
    if(knew):
       print("Write  new      key file:",defbind[i].keyfi)
    else:
       print("Update existing key file:",defbind[i].keyfi)
     
    #Write content to file:
    #fpkey = open(defbind[i].keyfi+"_NEW","w")
    fpkey = open(defbind[i].keyfi,"w")

    #Write basic parameters:
    #Arclink-Profile
    #if(defbind[i].alink != "NONE") and (defbind[i].alink != "None") and (defbind[i].alink != "none"):
     #  fpkey.write("arclink:%s\n" % (defbind[i].alink.strip()))

    #Arclink-Profile
    if(defbind[i].alinkacs != "NONE") and (defbind[i].alinkacs != "None") and (defbind[i].alinkacs != "none"):
       fpkey.write("access:%s\n" % (defbind[i].alinkacs.strip()))

    #Global-profile:
    if(defbind[i].globalprofile != "NONE") and (defbind[i].globalprofile != "None") and (defbind[i].globalprofile != "none"):
       fpkey.write("global:%s\n" % (defbind[i].globalprofile.strip()))    
 
    #scautopick-profile:
    if(defbind[i].scautopickprofile != "NONE") and (defbind[i].scautopickprofile != "None") and (defbind[i].scautopickprofile != "none"):
       fpkey.write("scautopick:%s\n" % (defbind[i].scautopickprofile.strip()))

    #Additional Pipelines:
    for k in range(len(defbind[i].pipelines)):
        fpkey.write("%s:%s\n" % (defbind[i].pipelines[k].module,defbind[i].pipelines[k].profile))

    #Close File:
    fpkey.close()

#Now check if existing key files are missing in binding-file:
print( "")
print("Summary")
print("=======")
print("Missing stations in",bindingfile,":")
for i in range(len(oldkey)):
    kmis = True
    for j in range(len(defbind)):
        if(defbind[j].keyfi.strip()==oldkey[i].strip()):
           kmis = False
    
    if(kmis):
       print("WARNING: Old keyfile %-20s is missing in file %s" % (oldkey[i],bindingfile))

#Now report keyfiles with multiple definitions:
print ("")
print ("Missing stations in",bindingfile,"with multiple definitions:")
for i in range(len(multidef)):
    print(multidef[i])

#Final summary:
print ("")
print ("Backup old keyfiles in current directory to",backupdir)
