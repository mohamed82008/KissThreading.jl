#!/bin/bash

echo Executing: $1
for i in `seq 1 $(nproc)`
do
    export JULIA_NUM_THREADS=$i
    julia $1
done

