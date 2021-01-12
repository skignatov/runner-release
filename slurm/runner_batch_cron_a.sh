#!/bin/bash
. /home1/07027/ignatov/.bashrc


#### Define your defaults here: #########
defremdir="/home/student/Documents/gwork"
defremcmd="g09"
OutputString=" SCF Done:  E("
maxcount=10000

defnproc=63
defmem="16000MB"
user="ignatov"

idle_time=2
maxcyc=5
InputFile=mg9.inp
curdir=/work/07027/ignatov/stampede2/runner/mg9
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

if [[ $InputFile == "" ]] ; then echo "InputFile is not set! USAGE: runner_batch_cron.sh <file>.inp" ; exit ; fi
if [ ! -f $InputFile ] ; then echo "Can not find InputFile $InputFile !" ; exit ; fi


# save/remove old files
if [  -e ${curdir}/runner_stop ] ; then rm ${curdir}/runner_stop ; fi
if [  -e ${curdir}/runner_shell_stop ] ; then rm ${curdir}/runner_shell_stop ; fi
if [  -e ${curdir}/runner_finished ] ; then rm ${curdir}/runner_finished ; fi
echo `date` > runner_started
echo "Runner started: " `date` > runner_log
if [  -e output.txt ] ; then mv output.txt output.txt_old ; fi






# Setup CRONTAB entry
crontime=5
croncmd="$PWD/runner_batch_cron_a.sh $InputFile >>${curdir}/res.log"
cronjob="*/$crontime * * * * $croncmd"
( crontab -l | grep -v -F "$croncmd" || : ; echo "$cronjob" ) | crontab -




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



# Start RUNNER
$PWD/runner.x $InputFile cron &
sleep 2


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

while [ $icyc -lt $maxcyc ]
do
    icyc=$(( icyc + 1 ))
    echo -e "\nCycle $icyc --" `date`


    #########################
    #      Monitor jobs     #
    #########################
    
	    squeue -u $user > squeue.txt
	    sleep 1
#echo "aaa" > squeue.txt
##cp procno.txt squeue.txt
#logfile=${jobname/".gjf"/".log"}
#touch $logfile

    arr_dirstat=( )
    for iwd in ${!arr_active[@]}
    do
	arr_dirstat[$iwd]=1	#dirstat: ready- initialization
    done
echo ${arr_active[@]}
echo ${arr_dirstat[@]}
    
    arr_filsub=( )
    ls ./sub >dirsub.txt
    while IFS= read -r file
    do
	arr_filsub+=($file)
    done <"dirsub.txt"

    nsub=${#arr_filsub[@]}
    nrunning=0
        
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

	cond=0
	procnofile="procno.txt"
	if [ ! -f "$procnofile" ] ; then arr_dirstat[$iwd]=1 ; cd $curdir ; continue ; fi   #dirstat: ready
	if [ -f "failed.txt"    ] ; then arr_dirstat[$iwd]=4 ; cd $curdir ; continue ; fi   #dirstat: failed
	while IFS= read -r file
    	do
	    words=($file)
	    procno=${words[0]}
	    jobname=${words[1]}
	done < "${procnofile}"

echo "iwd procno jobname $iwd $procno $jobname"

		
	if [[ $jobname==$subname ]]; then

	    cond=`grep -i $procno "$curdir/squeue.txt" | wc -l`
	    echo "in $wd cond $cond"
	    if (( "$cond" == 0)); then
		logfile=${jobname/".gjf"/".log"}
echo "logfile $logfile"
		if [ -e $logfile ] ; then 
		    arr_dirstat[$iwd]=3  # dirstat: done
		    mv $logfile ${curdir}/out/$logfile
    		    rm ${curdir}/sub/${jobname}_$iwd
    		    rm ${jobname}
		    nrunning=$(( nrunning - 1 ))
    		    processed=$(( processed + 1 ))
    		    nsub=$(( nsub - 1 ))
        	    echo "Job $procno  $jobname finished on $date  Processed: $processed"
        	    echo "Job $procno  $jobname finished on $date  Processed: $processed" >> ${curdir}/res.log
		    arr_dirstat[$iwd]=1  # dirstat: ready
echo "$iwd $wd $cond $logfile exists -- ${arr_dirstat[$iwd]}"
		else
		    arr_dirstat[$iwd]=4	#dirstat: failed
echo "$iwd $wd $cond $logfile does not exist -- ${arr_dirstat[$iwd]}"
		fi
	    else
	        arr_dirstat[$iwd]=2				  #dirstat: busy
	        echo "Job in $wd  - $jobname is running. PID $procno"
	        nrunning=$(( nrunning +1 ))
	    fi
	fi
	cd ${curdir}
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
    ls ./inp/*.gjf > input.txt
    datfile="input.txt"
    arr_filname=( )
    while IFS= read -r file
    do 
        arr_filname+=($file)
    done < "${datfile}"
    count=${#arr_filname[@]}

echo "filnames $count"

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
		pname="p"${pname#geo-000}
		pname=${pname/"-"/"x"}
		
		if [ ${arr_dirstat[$iwd]} -eq 1 ]
		then
echo 3
		    cp ${arr_filname[$ifil]} ./${wd}/${jobname}
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
			echo "${words[@]}" >> $wd/batch.run
		    done < "${bpatfile}"
echo 3b
		    cp ${inpname} ./sub/${jobname}_$iwd
		    mv ${inpname} ./out/${jobname}
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

		( exec sbatch $curdir/$wd/batch.run > $curdir/$wd/tmp )
		sleep 5
		
echo "4aa $PWD"
#touch tmp
#echo "Submitted batch job 1234$iwd" > tmp


		res=`cat tmp | tail -1 | grep "Submitted batch job" | wc -l`
		if [ $res -eq 1 ] ; then
echo 4a
		    jobnum=$(grep "." tmp | tail -1)
		    jobnum=${jobnum/"Submitted batch job "/""}
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
#exit


    ######################
    #   Check for finish #
    ######################
    if [ $icyc -gt $maxcyc ]
    then
       rm ${curdir}/runner_started
       echo `date` > runner_finished
       break
    fi
    if [ -e runner_stop ] || [ -e runner_shell_stop1 ]
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


