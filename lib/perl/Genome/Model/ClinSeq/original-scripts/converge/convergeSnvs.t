#!/usr/bin/env perl
use strict;
use warnings;
use above "Genome";
use Test::More tests => 4;
use Genome::Model::ClinSeq::Command::Tester qw(run_and_diff);

run_and_diff(
    command => '$script_dir/converge/convergeSnvs.pl  --model_group_id=65642 --outdir=$output_dir  --label=BRAF  --verbose=1',
    results_version => '2013-03-05',
    eventual_class => 'Genome::Model::ClinSeq::Command::Converge::Snvs',
);

