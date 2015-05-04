#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT}=1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}=1;
    $ENV{NO_LSF}=1;
}

use above 'Genome';
use Genome::SoftwareResult;
use Test::More;
use Genome::Test::Factory::SoftwareResult::User;

if (Genome::Config->arch_os ne 'x86_64') {
    plan skip_all => 'requires 64-bit machine';
}

my $refbuild_id = 101947881;
my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get($refbuild_id);
ok($ref_seq_build, 'human36 reference sequence build') or die;

my $result_users = Genome::Test::Factory::SoftwareResult::User->setup_user_hash(
    reference_sequence_build => $ref_seq_build,
);

#Parsing tests
my $det_class_base = 'Genome::Model::Tools::DetectVariants2';
my $dispatcher_class = "${det_class_base}::Dispatcher";

my $tumor_bam = Genome::Config::get('test_inputs') . "/Genome-Model-Tools-DetectVariants2-Dispatcher/flank_tumor_sorted.bam";
my $normal_bam = Genome::Config::get('test_inputs') . "/Genome-Model-Tools-DetectVariants2-Dispatcher/flank_normal_sorted.bam";

# Test dispatcher for running a simple single detector case
my $test_working_dir = File::Temp::tempdir('DetectVariants2-Dispatcher-detectorXXXXX', CLEANUP => 1, TMPDIR => 1);
my $detector_test = $dispatcher_class->create(
    snv_detection_strategy => 'samtools r599',
    output_directory => $test_working_dir,
    reference_build_id => $refbuild_id,
    aligned_reads_input => $tumor_bam,
    control_aligned_reads_input => $normal_bam,
    aligned_reads_sample => 'TEST',
    result_users => $result_users,
);
ok($detector_test, "Object to test a detector case created");
$detector_test->dump_status_messages(1);
ok($detector_test->execute, "Execution completed successfully.");
ok($detector_test->_workflow_result->{snv_result_id}, 'snv_result_id defined in workflow result');
ok($detector_test->_workflow_result->{snv_result_class}, 'snv_result_class defined in workflow result');
ok($detector_test->snv_result, 'snv_result defined on command');

done_testing();
