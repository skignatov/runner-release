#!/bin/bash
#PBS -N %%%
#PBS -l nodes=1:ppn=12

export GAUSS_LFLAGS='-opt "Tsnet.Node.Lindarsharg:ssh"'
cd $PBS_O_WORKDIR

inputfile=@@@
output=${inputfile%.gjf}.log

g09 <$PWD/${inputfile} >$PWD/${output}




