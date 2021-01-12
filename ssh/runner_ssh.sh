#!/bin/bash
set -e

#### Define your defaults here: #########
defremdir="/home/student/Documents/gwork"
defremcmd="g09"
user="student"
idle_time=30
defnproc=4
defmem="6000MB"
OutputString=" SCF Done:  E("
maxcount=10000
maxcyc=10000
#########################################

#ATTENTION! Linux utilities NMAP and SSHPASS have to be present on your system for proper work of this script! 
#           (use yast, yum ... to install them)
#

declare -a arr_filname
declare -a arr_filname_tmp
declare -a arr_node
declare -a arr_nodstat
declare -a arr_nodprog
declare -a arr_nodfree
declare -a arr_nodeup
declare -a arr_active
declare -a arr_remdir
declare -a arr_remcmd
declare -a arr_nproc
declare -a arr_mem
declare -a arr_u
declare -a arr_p
declare -a words
declare -a states
declare -a arr_hang_i
declare -a arr_hang_t

starttime=$SECONDS
submitted=0
processed=0
states=( "READY" "BUSY" "DONE" )

# make necessary directories if absent
if [ ! -d inp ] ; then mkdir inp ; fi
if [ ! -d out ] ; then mkdir out ; fi
if [ ! -d arc ] ; then mkdir arc ; fi
if [ ! -d sub ] ; then mkdir sub ; fi
if [ ! -d hlp ] ; then mkdir hlp ; fi


# save/remove old files
if [  -e runner_stop ] ; then rm runner_stop ; fi
if [  -e runner_shell_stop ] ; then rm runner_shell_stop ; fi
if [  -e runner_finished ] ; then rm runner_finished ; fi
echo `date` > runner_started
echo "Runner started: " `date` > runner_log
if [  -e output.txt ] ; then mv output.txt output.txt_old ; fi


# Functions used below
get_nodprog(){
        res=`nmap ${arr_node[$inod]} -PN -p ssh | grep open | wc -l`
    	if [ $res -eq 0 ] ; then arr_nodprog[$inod]=-1 ; res_file=-1 ; return ; fi
        remotedir=${arr_remdir[$inod]}
        arr_nodprog[$inod]=0
#        echo "nodprog1  ${arr_nodprog[$inod]}"
        res_prog1a=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep ${chkfile} | grep -v grep | wc -l"`   # Gaussian, our job, our file
#        sleep 1
        res_prog1b=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep -v grep | wc -l"`   # Gaussian, our job, another file
#        sleep 1
        res_prog1c=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep -v grep |  wc -l"`                      # Gaussian, third-party job
#        sleep 1
        if [ $res_prog1a -eq 1 ] ; then arr_nodprog[$inod]=1 ; fi
        if [ $res_prog1a -eq 0 ] && [ $res_prog1b -eq 1 ] ; then arr_nodprog[$inod]=2 ; fi
        if [ $res_prog1b -eq 0 ] && [ $res_prog1c -eq 1 ] ; then arr_nodprog[$inod]=3 ; fi
        
        res_prog2a=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [l]mp_mpi | grep -v grep |  wc -l"`   # lammps
        sleep 1
        res_prog2b=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [g]mx | grep -v grep |  wc -l"`   # gromacs
        sleep 1
        res_prog2c=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [P]crystal | grep -v grep |  wc -l"`   # crystal
        sleep 1
        if [ $res_prog2a -eq 1 ] ; then arr_nodprog[$inod]=4 ;fi
        if [ $res_prog2b -eq 1 ] ; then arr_nodprog[$inod]=5 ;fi
        if [ $res_prog2c -eq 1 ] ; then arr_nodprog[$inod]=6 ;fi
#        echo "nodprog2  ${arr_nodprog[$inod]}"
        res_file=-1
        res_file=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/${oldfilelog}  && echo 1 || echo 0"` 
}


is_node_up(){
        res=`nmap ${arr_node[$inod]} -PN -p ssh | grep open | wc -l`
    	if [ $res -eq 0 ] 
	then 
	    arr_nodeup[$inod]=0
	    echo "Node " $inod " [ " ${arr_node[$inod]} "] is DOWN "
	else
	    arr_nodeup[$inod]=1
	    nodesUP=$(( nodesUP+1 ))
	    echo -n "Node " $inod " [ " ${arr_node[$inod]} "] is UP   "
        fi
}



is_nodefree(){
        res1=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep -v grep |  wc -l"`   # Gaussian
#        sleep 1
        res2=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [l]mp_mpi | grep -v grep |  wc -l"`   # lammps
#        sleep 1
        res3=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [g]mx  | grep -v grep |  wc -l"`   # gromacs
#        sleep 1
        res4=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [P]crystal | grep -v grep |  wc -l"`   # crystal
        res_nodefree=$(( res1 + res2 + res3 + res4 ))
}


check_hanging_job(){
        res_prog103=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep l103.exe | grep [G]au- | grep ${remotedir} | grep ${chkfile} | grep -v grep | wc -l"`   # Check for hanging l103
        if [ $res_prog103 -eq 1 ] 
        then 
    	    it=${arr_hang_i[$inod]}
    	    it=$(( it +1 ))
    	    arr_hang_i[$inod]=$it
    	    if [ ${arr_hang_i[$inod]} -eq 1 ]; then arr_hang_t[$inod]=$SECONDS ; fi
    	    if [ ${arr_hang_i[$inod]} -ge 3 ] 
    	    then
    	        t0=${arr_hang_t[$inod]}
    	        tt=$SECONDS
    		dt=$(( tt - t0 ))
    		if [ $dt -gt 600 ]
    		then
    		    echo " WARNING! l103 is hanging more than 10 min on [ ${arr_node[$inod]} ]. Hangout?..."
# Uncomment the code below to automatically terminate a hanging job
    		    resstr=(`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep l103.exe | grep ${chkfile} | grep -v grep"`)
    		    procno=${resstr[1]}
                   echo "Process $procno on node ${arr_node[$inod]} will be terminated"
    		    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "kill $procno"
		    res_prog1a=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep ${chkfile} | grep -v grep | wc -l"`   # Gaussian, our job, our file
    		    if [ $res_prog1a -eq 0 ]
    		    then 
    			echo "Hanging job $oldfile on node [ ${arr_node[$inod]} ] was terminated at `date`"
    		    else
        		echo "Cannot terminate the hanging job $oldfile on node [ ${arr_node[$inod]} ] ProcNo $procno . Check this job manually."
        	    fi
#######################################
    		    arr_hang_i[$inod]=0
        	    arr_hang_t[$inod]=0
    		fi
    	    fi
    	else
    	    arr_hang_i[$inod]=0
    	    arr_hang_t[$inod]=0
    	fi
}


download_resfile(){
        res_bus1=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/$bname  && echo 1 || echo 0"` 
        sleep 1
        res_busy=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/busy  && echo 1 || echo 0"` 
        sleep 1
        res_file=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/${oldfilelog}  && echo 1 || echo 0"` 
        sleep 1
        res_done=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/done  && echo 1 || echo 0"` 
        sleep 1
        res_read=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/ready && echo 1 || echo 0"` 
        sleep 1
        res_prog1=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep -v grep | wc -l"` 
        sleep 1
        res_prog2=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep -v grep |  wc -l"` 
        sleep 1
        res_prog3=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${remotedir} | grep -v grep |  wc -l"` 
        res_prog=0
        if [ $res_prog1 -ge 1 ] || [ $res_prog2 -ge 1 ] || [ $res_prog3 -ge 1 ] ; then res_prog=1 ;  fi
        igetlog=0
        if [ $res_prog -eq 0 ] && [ $res_file -eq 1 ] ; then igetlog=1 ; echo -n " Job is finished. " ; fi  # program is crashed
    	if [ $res_prog -eq 1 ] && [ $res_bus1 -eq 0 ] && [ $res_file -eq 1 ] ; then igetlog=1 ; echo -n " Program is working on other job. " ; fi  # program is working on other files
    	if [ $igetlog -eq 1 ] 
    	then
    	    echo "Downloading output."
    	    sshpass -p${arr_p[$inod]} scp "${arr_u[$inod]}@${arr_node[$inod]}:${remotedir}/${oldfilelog}" "./out/${oldfilelog}"
    	    echo "rm busy " $icyc $inod $ifn
    	    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/busy && rm ${remotedir}/busy || : " 
        sleep 1
    	    echo "rm done " $icyc $inod $ifn
    	    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/done && rm ${remotedir}/done || : "  
        sleep 1
    	    echo "touch ready " $icyc $inod $ifn
    	    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/ready && : || touch ${remotedir}/ready" 
    	    echo "label D" $icyc $inod $ifn
    	    processed=$(( processed+1 ))
	    echo "Downloaded file $oldfilelog from ${arr_node[$inod]} at" `date` " Processed now: $processed"
    	    echo "$oldfilelog downloaded at " `date` >> runner_log
	    #echo "$oldfilelog" `grep "$OutputString" "./out/$oldfilelog" | tail -n 1` >> output.txt
    	    echo "label 0a"
    	    rm ${oldfilenode}
    	    echo "label 0b"
#    	    arr_nodstat[$inod]=0
    	    echo $maxcount $maxcyc $submitted $processed > info.txt
    	elif [ $res_file -eq 0 ]
    	then
    	    echo " Output file not found. Repeating input submission."
    	    mv ${oldfilenode} ./inp/${oldfile}
    	    echo "label 1b"
#    	else
#    	    echo " Job in progress."
        fi
}

clear_node_list(){
   arr_node=( )
   arr_active=( )
   arr_u=( )
   arr_nproc=( )
   arr_mem=( )
   arr_remcmd=( )
   arr_remdir=( )
   arr_busy=( )
   arr_nodeup=( )
   arr_p=( )
   arr_nodstat=( )
}

read_nodes(){
# nodes file
nodefile="${1:-nodes.txt}"
[ ! -f "$nodefile" ] && { echo "$0 - File $nodefile not found."; exit 1; }

#nodelist
while IFS= read -r file
do
   [[ $file = \#* ]] && continue
   words=($file)
#   echo "splitted line:  ${words[0]} - ${words[1]} - ${words[2]}"
   arr_node+=(${words[0]})
   echo "${words[0]}"
   arr_active+=( ${words[1]} )
   arr_u+=( ${words[2]} )
   arr_nproc+=( ${words[3]} )
   arr_mem+=( ${words[4]} )
   if [ "${words[5]}" == "" ] ; then words[5]="$defremcmd" ; fi
   arr_remcmd+=(${words[5]})
   if [ "${words[6]}" == "" ] ; then words[6]="$defremdir" ; fi
   arr_remdir+=(${words[6]})
   arr_busy+=(0)
   arr_nodeup+=(0)
   arr_p+=( "pass1" )
   arr_nodstat+=(0)
done < "${nodefile}"
nodes=${#arr_node[@]}
arr_p[0]="pass2"
arr_p[1]="pass3"
}


#############################
#############################
##                         ##
##        MAIN LOOP        ##
##                         ##
#############################
#############################

echo -e "\nMain loop"
#processed=0
#submitted=0
icyc=-1

while [ $icyc -lt $maxcyc ]
do
    icyc=$(( icyc + 1 ))
    echo -e "\nCycle $icyc --" `date`

  if [ $(( icyc % 1 )) -eq 0 ] 
  then

    ############################################
    #    Read node list from file nodes.txt    #
    ############################################
    clear_node_list
    read_nodes
  
    ############################################
    #    Check if nodes are UP and active      #
    ############################################
    echo "Check if nodes are UP and active"
    nodesUP=0
    activenodes=0
    for inod in ${!arr_node[@]}
    do
	if [ ${arr_active[$inod]} -eq 0 ] ; then echo "Node " $inod " [ " ${arr_node[$inod]} " ] is forbidden by user" ;  continue ; fi

        nodeup0=${arr_nodeup[$inod]} 
        is_node_up
	if [ ${arr_nodeup[$inod]} -eq 0 ] ; then continue ; fi
#        if [ ${arr_nodeup[$inod]} -eq $nodeup0 ] && [ $icyc -gt 1 ] ; then echo " " ; continue ; fi
        
        is_nodefree
        if [ $res1 -gt 0 ] ; then 
    	    res1a=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "ps aux | grep [.]exe | grep [G]au- | grep ${arr_remdir[$inod]} | grep -v grep | wc -l"`   # Our copy of Gaussian
    	fi

    	if [ $res_nodefree -eq 0 ]
    	then 
    	    arr_nodprog[$inod]=0
    	    echo "Node is free" 
    	    activenodes=$(( activenodes + 1 ))
    	elif [[ $res1a -eq $res1 ]] && [[ $res1 -gt 0 ]]
    	then 
    	    arr_nodprog[$inod]=1
    	    echo "Node is busy with current job"
    	    activenodes=$(( activenodes + 1 ))
    	else
    	    arr_nodprog[$inod]=99
    	    echo "Node is busy"
    	fi 
    	
	# Make node directory if absent
	if [ ${arr_nodstat[$inod]} -eq 1 ] ; then continue ; fi
        remotedir=${arr_remdir[$inod]}
    	res=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -d ${remotedir} && echo 1 || echo 0"` 
	if [ $res -eq 0 ] ; then  sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "mkdir ${remotedir}"; fi

    	res=`sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "test -e ${remotedir}/work && echo 1 || echo 0"` 
	if [ $res -eq 0 ]
	then  
	    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "touch ${remotedir}/work"
	    sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "chmod 777 ${remotedir}/work"
	fi
	arr_nodstat[$inod]=1

    done
    echo "### " $activenodes " nodes are active"
  fi

    #######################################################
    #Download files submitted earlier (if job is finished)#
    #######################################################
    
    echo `ls ./sub/*.gjf* > oldfiles.txt 2>/dev/null`
    arr_filname_tmp=( )
    oldfiles="${1:-oldfiles.txt}"
    while IFS= read -r file
    do 
        arr_filname_tmp+=($file)
    done < "${oldfiles}"

    for ifn in "${!arr_filname_tmp[@]}";
    do
	oldfilenode=${arr_filname_tmp[$ifn]}
        oldfile=${oldfilenode%__*}
        oldfile=${oldfile#./sub/}
        oldfilelog=${oldfile%.gjf}.log
        inod=${oldfilenode#*__}
        bname="busy"$oldfile
	echo -n "Checking submitted job $oldfile on node $inod [ ${arr_node[$inod]} ] :"

	if [ ${arr_active[$inod]} -eq 0 ] ; then is_node_up ; fi
	if [ ${arr_nodeup[$inod]} -eq 0 ]; then echo " Node is currently DOWN" ; continue ; fi
        remotedir=${arr_remdir[$inod]}
	chkfile=${oldfile%.gjf}.chk

	# check for the working programs and jobs
        get_nodprog
        nodprog=${arr_nodprog[$inod]}
        if [ $nodprog -eq -1 ] ; then echo "Node is currently DOWN" ; mv ${oldfilenode} ./hlp/${oldfile} ; continue ;fi
        if [ $nodprog -eq  0 ] ; then echo "Node is free" ; fi
        if [ $nodprog -eq  1 ] ; then echo "Job is running" ; fi
        if [ $nodprog -eq  2 ] ; then echo "Another file of this job is running" ; fi
        if [ $nodprog -eq  3 ] ; then echo "Third-party copy of Gaussian is running" ; fi
        if [ $nodprog -eq  4 ] ; then echo "LAMMPS is running" ; fi
        if [ $nodprog -eq  5 ] ; then echo "GROMACS is running" ; fi
        if [ $nodprog -eq  6 ] ; then echo "CRYSTAL is running" ; fi
    	    

#	download_resfile()   #<-- Old download procedure

	# download the completed/terminated jobs
    	if [ $nodprog -ne 1 ] && [ $res_file -eq 1 ] 
    	then
    	    echo -n "Downloading output. "
    	    sshpass -p${arr_p[$inod]} scp "${arr_u[$inod]}@${arr_node[$inod]}:${remotedir}/${oldfilelog}" "./out/${oldfilelog}"
    	    processed=$(( processed+1 ))
	    echo "Downloaded file $oldfilelog from ${arr_node[$inod]} at" `date` " Processed now: $processed"
    	    echo "$oldfilelog downloaded at " `date` >> runner_log
    	    rm ${oldfilenode}
#    	    arr_nodstat[$inod]=0
    	elif [ $nodprog -ne 1 ] && [ $res_file -eq 0 ]
    	then
    	    echo " WARNING! Output file not found. Repeating input submission."
    	    mv ${oldfilenode} ./inp/${oldfile}
        fi

	# check for hanging jobs each 10 cycles
	if [ $(( icyc % 10 )) -eq 0 ] ; then check_hanging_job ; fi

    done


    ########################
    #    Get input file    #
    ########################
    echo `ls ./inp/*.gjf > input.txt 2>/dev/null`
    datfile="${1:-input.txt}"
    [ ! -f "$datfile" ] && { echo "$0 - File $datfile not found."; exit 1; }
    arr_filname=( )
    while IFS= read -r file
    do 
        arr_filname+=($file)
    done < "${datfile}"
    count=${#arr_filname[@]}
    
    
    #########################
    #    Run input files    #
    #########################
    
    for inod in "${!arr_node[@]}";
    do
	arr_nodfree[$inod]=0
	if [ ${arr_active[$inod]}  -eq 0 ]; then echo "Node $inod [ ${arr_node[$inod]} ] is inactive" ;continue ; fi
        if [ ${arr_nodeup[$inod]}  -eq 0 ]; then echo "Node $inod [ ${arr_node[$inod]} ] is down"     ;continue ; fi
        if [ ${arr_nodprog[$inod]} -gt 0 ]; then echo "Node $inod [ ${arr_node[$inod]} ] is busy"     ;continue ; fi 
        res=`nmap ${arr_node[$inod]} -PN -p ssh | grep open | wc -l`
    	if [ $res -eq 0 ] ; then echo "Node $inod [ ${arr_node[$inod]} ] is unreachable"              ; continue ; fi
	is_nodefree
	if [ $res_nodefree -eq 0 ] ; then arr_nodfree[$inod]=1 ; echo "Node $inod [ ${arr_node[$inod]} ] is free" ; fi
    done

    for ifil in ${!arr_filname[@]}
    do
        for inod in "${!arr_node[@]}";
	do
	    if [ ${arr_nodfree[$inod]} -eq 1 ] 
	    then
		remotedir=${arr_remdir[$inod]}
		inpname=${arr_filname[$ifil]}
		jobname=${inpname#./inp/}
		bname="busy"$jobname
		
		echo "cd ${remotedir}" > work
    		echo "rm ready" >> work
    		echo "rm done" >> work
    		echo "touch busy" >> work
    		echo "touch $bname" >> work
		echo "${arr_remcmd[$inod]} $jobname" >> work
		echo "rm busy" >> work
		echo "rm $bname" >> work
		echo "rm ${jobname%.gjf}.chk" >> work
		echo "echo "  ${jobname%.gjf}.log "> done" >> work
	    
        	#echo $ifil $inod "${arr_filname[$ifil]}" "${arr_u[$inod]}@${arr_node[$inod]}:${remotedir}/$jobname"
        	sshpass -p${arr_p[$inod]} scp "$inpname" "${arr_u[$inod]}@${arr_node[$inod]}:${remotedir}/$jobname"
		sshpass -p${arr_p[$inod]} scp "./work" "${arr_u[$inod]}@${arr_node[$inod]}:${remotedir}/work"
		sshpass -p${arr_p[$inod]} ssh ${arr_u[$inod]}@${arr_node[$inod]} "${remotedir}/work < /dev/null > ${remotedir}/work.log 2>&1 &"

	        cp "$inpname" "./sub/"${jobname}__$inod
        	mv "$inpname" "./out/"
        	submitted=$(( submitted+1 ))
        	echo "File ${arr_filname[$ifil]}  started on ${arr_node[$inod]} at " `date`  "Started now: $submitted"
        	echo "${remotedir}/${arr_filname[$ifil]}  started on ${arr_node[$inod]} at " `date` >> runner_log
        	arr_nodfree[$inod]=0
		break
    	    fi 
        done    
    done


    ######################
    #   Check for finish #
    ######################
    if [ $icyc -gt $maxcyc ]
    then
       rm runner_started
       echo `date` > runner_finished
       break
    fi
    if [ -e runner_stop ] || [ -e runner_shell_stop ]
    then
       rm runner_started
       echo "runner stopped by external request" `date` >> runner_finished
       echo "runner stopped by external request" `date` >> runner_log
	break
    fi
    echo "Idle time $idle_time sec"
    sleep $idle_time
    
done

######################################
# END OF MAIN LOOP.  FINAL SECTION   #
######################################

tsec=$(( $SECONDS - starttime ))
tmin=$(( tsec / 60 ))
thrs=$(( tmin / 60 ))

echo "##########" >> runner_log
echo "Runner finished successfully at" `date` " -- Runtime: $tsec sec = $tmin min = $thrs hrs"  >> runner_log
grep "done" runner_log  >> runner_finished
sleep 10
echo -e "\nRunner finished successfully at" `date`


