#!/usr/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More tests => 5;

use constant SUCCESSFUL_JOB => 'DONE';
use constant FAILED_JOB => 'EXIT';

use_ok('Genome::Sys') or die;


my %expected_job_statuses;

subtest 'submit job' => sub {
    plan tests => 1;

    my $cmd = 'ls ~';
    my $job_id = Genome::Sys->bsub(
        queue => Genome::Config::get('lsf_queue_short'),
        cmd => $cmd,
    );
    ok($job_id, "bsubbed $cmd, got job id back");
    $expected_job_statuses{$job_id} = SUCCESSFUL_JOB;
};

subtest 'submit failing job' => sub {
    plan tests => 1;

    my $cmd = 'exit 1';
    my $job_id = Genome::Sys->bsub(
        queue => Genome::Config::get('lsf_queue_short'),
        cmd => $cmd
    );
    ok($job_id, "bsubbed $cmd, got job id back");
    $expected_job_statuses{$job_id} = FAILED_JOB;
};

subtest 'get job statuses' => sub {
    plan tests => 3;

    my %job_statuses = Genome::Sys->wait_for_lsf_jobs(keys %expected_job_statuses);
    ok(%job_statuses, 'got job status hash back from wait_for_lsf_jobs method');

    is(scalar(keys %job_statuses),
       scalar(keys %expected_job_statuses),
       'job status hash has same number of keys as submitted jobs');

    is_deeply(\%job_statuses, \%expected_job_statuses, 'Job statuses are as expected');
};

subtest 'bsub_and_wait_for_completion' => sub {
    plan tests => 1;

    my @cmds = (['ls', '~'],
                'exit 1',
               );
    my @statuses = Genome::Sys->bsub_and_wait_for_completion(
                        queue => Genome::Config::get('lsf_queue_short'),
                        cmds => \@cmds,
                    );
    is_deeply(\@statuses,
              [SUCCESSFUL_JOB, FAILED_JOB],
              'statuses are correct');
};
