#!/bin/bash

for i in `seq 1 $(nproc)`
do
    echo Threads: $i
    export JULIA_NUM_THREADS=$i
    julia runtests.jl
done

