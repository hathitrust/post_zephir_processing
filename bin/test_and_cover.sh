#!/bin/bash

cover -test -report Coveralls -make 'prove; exit $?'
