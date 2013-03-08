#!/bin/sh

perlbrew install --notest perl-5.16.0
perlbrew use perl-5.16.0
perl --version | head -n2

perlbrew install-cpanm
cpanm --help | head -n1
cpanm amon2
cpanm carton

