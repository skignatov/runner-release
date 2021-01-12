#!/bin/bash
#. /home1/07027/ignatov/.bashrc


#########################################
#### Define your defaults here: #########
#########################################

# These are important parameters! Check it carefully!
user="IgnatovSK"
curdir=$PWD
InputFile=mg32.inp
idle_time=300
maxcyc=1000000
jletter="t"

#for PBS only  (prefix added by qsub to JobNo)
compname=".master1.cyberia.tsu.ru"


# not obligatory
defremdir="/home/student/Documents/gwork"
defremcmd="g09"
OutputString=" SCF Done:  E("
maxcount=10000
defnproc=63
defmem="16000MB"

#########################################
#########################################
#########################################

#ATTENTION! Linux utilities NMAP and SSHPASS have to be present on your system for proper work of this script! 
#           (use yast, yum ... to install them)
#

declare -a arr_wd
declare -a arr_active
declare -a arr_filname
declare -a arr_filname_tmp
declare -a arr_filsub

declare -a arr_node
declare -a arr_nodstat
declare -a arr_nodprog
declare -a arr_nodfree
declare -a arr_nodeup
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
declare -a arr_bat

cd $curdir


starttime=$SECONDS
submitted=0
processed=0
states=( "READY" "BUSY" "DONE" )

if [[ $InputFile == "" ]] ; then echo "InputFile is not set! USAGE: runner_batch_??.sh <file>.inp" ; exit ; fi
if [ ! -f $InputFile ] ; then echo "Can not find InputFile $InputFile !" ; exit ; fi


# save/remove old files
if [  -e ${curdir}/runner_stop ] ; then rm ${curdir}/runner_stop ; fi
if [  -e ${curdir}/runner_shell_stop ] ; then rm ${curdir}/runner_shell_stop ; fi
if [  -e ${curdir}/runner_finished ] ; then rm ${curdir}/runner_finished ; fi
echo `date` > runner_started
echo "Runner started: " `date` > runner_log
if [  -e output.txt ] ; then mv output.txt output.txt_old ; fi






# Setup CRONTAB entry
crontime=10
croncmd="${curdir}/$0 $InputFile >>${curdir}/res.log"
cronjob="*/$crontime * * * * $croncmd"
#( crontab -l | grep -v -F "$croncmd" || : ; echo "$cronjob" ) | crontab -


#exit

#( crontab -l | grep -v -F "$croncmd" &&  echo "" || : ) | crontab -
remove_crontab_entry(){
( crontab -l | grep -v -F "$croncmd" ) | crontab -
}

#remove_crontab_entry
#exit


# Make all necessary dirs
if [ ! -d ./inp ] ; then mkdir ./inp ; fi
if [ ! -d ./out ] ; then mkdir ./out ; fi
if [ ! -d ./arc ] ; then mkdir ./arc ; fi
if [ ! -d ./sub ] ; then mkdir ./sub ; fi
if [ ! -d ./hlp ] ; then mkdir ./hlp ; fi
if [ ! -d ./add ] ; then mkdir ./add ; fi
if [ ! -d ./usd ] ; then mkdir ./usd ; fi
sleep 1

run_runner(){
	$curdir/runner.x $InputFile cron &
	echo "Runner started in a cron mode. Sleep for 30 sec."
	sleep 30
}

get_input_files(){
    cd ${curdir}
    ls ./inp/*.gjf > input.txt
    arr_filname=( )
    while IFS= read -r file
    do 
        arr_filname+=($file)
    done < "input.txt"
    count=${#arr_filname[@]}
}


# Initial start of RUNNER
#$curdir/runner.x $InputFile cron &
#sleep 10
run_runner


# Workdirs file
wdfile="workdirs.txt"
[ ! -f "$wdfile" ] && { echo "$0 - File $wdfile not found."; exit 1; }
words=()
arr_bat=()
# Workdirs list
while IFS= read -r file
do
   [[ $file = \#* ]] && continue
   words=($file)
   #echo "splitted line:  ${words[0]} - ${words[1]} - ${words[2]}"
   arr_wd+=(${words[0]})
   #echo "${words[0]}"
   arr_active+=( ${words[1]} )
   arr_bat+=( ${words[3]} )
done < "${wdfile}"


# Make workdirs
for iwd in ${arr_wd[@]}
do
    if [ ! -d $iwd ] ; then mkdir $iwd ; fi
done




#############################
#############################
##                         ##
##        MAIN LOOP        ##
##                         ##
#############################
#############################

echo -e "\nMain loop"
processed=0
submitted=0
icyc=-1
sq_fld=0

while [ $icyc -lt $maxcyc ]
do
    icyc=$(( icyc + 1 ))
    echo -e "\nCycle $icyc --" `date`

    nproc0=$processed

    #########################
    #      Monitor jobs     #
    #########################
    

    # First, obtain queueu info
    if [ -e ${curdir}/squeue.txt ] ; then mv ${curdir}/squeue.txt ${curdir}/squeue.txt_$sq_fld ; fi
#    squeue -u $user > ${curdir}/squeue.txt
    qstat -u $user > ${curdir}/squeue.txt
    sleep 5
    if [ ! -f ${curdir}/squeue.txt ] 
    then 
	sq_fld=$(( sq_fld + 1 ))
	if [ sq_fld -le 10 ] 
	then
	    sleep 15
	    continue 
	else
	    echo " Can not obtain QUEUE info. SQUEUE failed $sq_fld times. Check your system/server/shell/modules and SQUEUE.TXT_ files.."
	    break
	fi
    fi
    sq_fld=0
    
#echo "aaa" > squeue.txt
##cp procno.txt squeue.txt
#logfile=${jobname/".gjf"/".log"}
#touch $logfile

    # Initialize  DIR STATES array -- arr_dirstat
    arr_dirstat=( )
    for iwd in ${!arr_active[@]}
    do
	arr_dirstat[$iwd]=1	#dirstat: initialization -- ready(1)
    done
echo ${arr_active[@]}
echo ${arr_dirstat[@]}



    # Check if some jobs have already been submitted    
    arr_filsub=( )
    ls ./sub >dirsub.txt
    while IFS= read -r file
    do
	arr_filsub+=($file)
    done <"dirsub.txt"
    nsub=${#arr_filsub[@]}
    nrunning=0
        
        
    # Check STATES of the running jobs
    # First, read subnames and wd from SUB dir
    for isub in ${!arr_filsub[@]}
    do
	filsub=${arr_filsub[$isub]}
	filsub=${filsub#./sub/}
	subname=${filsub%_*}
	iwd=${filsub#*_}
	echo $iwd $filsub $subname
	if [ ${arr_active[$iwd]} -eq 0 ] ; then continue ; fi
	wd=${arr_wd[$iwd]}
	cd $wd

echo "iwd wd filsub subname $iwd $wd $filsub  $subname"
	
	# Check if the file in wd has been queued -- read PROCNO.TXT file
	cond=0
	procnofile="procno.txt"
	if [ ! -f "$procnofile" ] ; then arr_dirstat[$iwd]=1 ; cd $curdir ; continue ; fi   #dirstat: ready (1)
	if [ -f "failed.txt"    ] ; then arr_dirstat[$iwd]=4 ; cd $curdir ; continue ; fi   #dirstat: failed sbatch (4)
	while IFS= read -r file
    	do
	    words=($file)
	    procno=${words[0]}
	    jobname=${words[1]}
	done < "${procnofile}"

echo "iwd procno jobname $iwd $procno $jobname"
	
	# Check if jobname in PROCNO.TXT corresponds to subname file in SUB. If YES job is runnig(state 2), finished(3->1), or filed(4). If NOT, wd is free (1) or failed to squeue the job (5)
	if [[ $jobname==$subname ]]; then

	    # WD contains proper jobname. Check if PROCNO from procno.txt is listed in SQUEUE.TXT
	    cond=`grep -i $procno "$curdir/squeue.txt" | wc -l`
	    echo "in $wd cond $cond"
	    if (( "$cond" == 0)); then		# there is NO necessary PROCNO in SQUEUE
		logfile=${jobname/".gjf"/".log"}
echo "logfile $logfile"
		if [ -e $logfile ] ; then 	# (NO procno in SQUEUE)  &  (LOGFILE is present in WD) -- job finished (done 3, then download and wd state 1)
		    arr_dirstat[$iwd]=3  # dirstat: done
		    mv $logfile ${curdir}/out/$logfile
    		    rm ${curdir}/sub/${jobname}_$iwd
    		    rm ${jobname}
		    #nrunning=$(( nrunning - 1 ))
    		    processed=$(( processed + 1 ))
    		    nsub=$(( nsub - 1 ))
        	    echo "Job $procno  $jobname finished on $date  Processed: $processed"
        	    echo "Job $procno  $jobname finished on $date  Processed: $processed" >> ${curdir}/res.log
		    arr_dirstat[$iwd]=1  # dirstat: ready
echo "$iwd $wd $cond $logfile exists -- ${arr_dirstat[$iwd]}"
		else							# (NO procno in SQUEUE)  &  (no LOGFILE in WD) -- Failed squeue ? (state 5)
		    arr_dirstat[$iwd]=5	#dirstat: failed
		    echo "$iwd $wd $cond $logfile does not exist -- ${arr_dirstat[$iwd]}"
		    cp procno.txt procno.failed_$procno
		fi
	    else							# (PROCNO is present in SQUEUE.TXT) -- Job is running or waiting in queue (state 2)
	        arr_dirstat[$iwd]=2				  #dirstat: busy
	        echo "Job in $wd  - $jobname is running. PID $procno"
	        nrunning=$(( nrunning +1 ))
	    fi
	fi
	cd ${curdir}		# Jobname is different from subname -- wd is free (1) or failed squeue (5)
	echo  $arr_dirstat[$iwd]
    done
    
    for iwd in ${!arr_active[@]}
    do
	echo "dir $iwd ${arr_wd[$iwd]} ${arr_active[$iwd]} ${arr_dirstat[$iwd]}"
    done
    
    echo "Files in sub dir: $nsub"
    echo "Jobs running    : $nrunning"

echo 2

    ########################
    #    Get input files   #
    ########################
    
    get_input_files
    if [ $count -eq 0 ]
    then
	run_runner
	get_input_files
    fi
    echo "files in INP dir: $count"

    #########################
    #    Run input files    #
    #########################
    
    for ifil in ${!arr_filname[@]}
    do
	echo "Running now $nrunning . Work directories ${#arr_wd[@]}"
	if [ $nrunning -ge ${#arr_wd[@]} ] ; then break ; fi
echo "File $ifil ${arr_filname[$ifil]} looking for free dir"
        for iwd in ${!arr_wd[@]}
	do
	    if [ ${arr_active[$iwd]} -ne 1 ] ; then continue ; fi
	    if [[ ${arr_dirstat[$iwd]} -eq 1 ]] || [[ ${arr_dirstat[$iwd]} -eq 4 ]] ; then
echo "dir for run $iwd ${arr_wd[$iwd]}"
		wd=${arr_wd[$iwd]}
		inpname=${arr_filname[$ifil]}
		jobname=${inpname#./inp/}
		pname=${jobname%.gjf}
		pname=${jletter}${pname#geo-000}
		pname=${pname/"-"/"x"}
		
		if [ ${arr_dirstat[$iwd]} -eq 1 ]
		then
echo 3
		    cp ${arr_filname[$ifil]} ${curdir}/${wd}/${jobname}
		    if [ -f ${curdir}/$wd/batch.run ] ; then rm ${curdir}/$wd/batch.run ; fi
#		    bpatfile="batch.run0"
		    bpatfile=${arr_bat[$iwd]}
		    [ ! -f "$bpatfile" ] && { echo "$0 - File $bpatfile not found."; exit 1; }
echo 3a
		    while IFS= read -r file
		    do
			words=($file)
		    #   echo "splitted line:  ${words[0]} - ${words[1]} - ${words[2]}"
			for i in "${!words[@]}" 
			do 
			    words[$i]=${words[$i]/"%%%"/$pname}
			    words[$i]=${words[$i]/"@@@"/$jobname}
			done
			echo "${words[@]}" >> ${curdir}/$wd/batch.run
		    done < "${bpatfile}"
echo 3b
		    cp ${inpname} ${curdir}/sub/${jobname}_$iwd
		    mv ${inpname} ${curdir}/out/${jobname}
		    nsub=$(( nsub + 1 ))
	        fi
	    

		cd ${curdir}/$wd
echo 4 $PWD

#export home=/home1/07027/ignatov
export work=/work/07027/ignatov/stampede2
export WORK=/work/07027/ignatov/stampede2
export scratch=/scratch/07027/ignatov
export SCRATCH=/scratch/07027/ignatov

#echo 111
#source /home1/07027/ignatov/.bashrc

echo 112

#		( exec sbatch ${curdir}/$wd/batch.run > ${curdir}/$wd/tmp )
		( exec qsub ${curdir}/$wd/batch.run > ${curdir}/$wd/tmp )
		sleep 5
		
echo "4aa $PWD"
#touch tmp
#echo "Submitted batch job 1234$iwd" > tmp


		res=`cat tmp | tail -1 | grep ".master1.cyberia.tsu.ru" | wc -l`
		if [ $res -eq 1 ] ; then
echo 4a
		    jobnum=$(grep "." tmp | tail -1)
		    jobnum=${jobnum/".master1.cyberia.tsu.ru"/""}
		    echo "$jobnum $jobname " `date` > procno.txt
		    if [ -e failed.txt ] ; then rm failed.txt ; fi
		    submitted=$(( submitted + 1 ))
		    echo "Started $jobname in ${arr_wd[$iwd]} "`date` " Submitted: $submitted"
		    nrunning=$(( nrunning +1 ))
		    arr_dirstat[$iwd]=2
		else
echo 4b
		    echo "$jobname " `date` > failed.txt
		    arr_dirstat[$iwd]=3
		    echo "Failed to start $jobname in ${arr_wd[$iwd]} "`date` " Will try to run at the next cycle"
		fi
		cd ${curdir}
echo 5
		break
	     fi
	     sleep 1
	done
     done

echo 7

    cd ${curdir}
    # Start RUNNER in a cron mode
    if [ $processed -gt $nproc0 ]
    then
#	$curdir/runner.x $InputFile cron &
#	echo "Runner started in a cron mode. Sleep for 30 sec."
#	sleep 30
	run_runner
    fi

echo 8

    ######################
    #   Check for finish #
    ######################
    if [ $icyc -gt $maxcyc ]
    then
       rm ${curdir}/runner_started
       echo `date` > runner_finished
       break
    fi
    if [ -e runner_stop ] || [ -e runner_shell_stop ]
    then
       rm ${curdir}/runner_started
       echo "runner stopped by external request" `date` >> runner_finished
       echo "runner stopped by external request" `date` >> runner_log
       remove_crontab_entry
	break
    fi
#    squeue -u $user
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


