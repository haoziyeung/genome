#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{NO_LSF} = 1;
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use File::Path;
use File::Temp;
use Test::More;
use above 'Genome';
use Genome::SoftwareResult;
use Genome::Test::Factory::SoftwareResult::User;

my $archos = `uname -a`;
if ($archos !~ /64/) {
    plan skip_all => "Must run from 64-bit machine";
}

use_ok('Genome::Model::Tools::DetectVariants2::Pindel');

my $refbuild_id = 101947881;
my $ref_seq_build = Genome::Model::Build::ImportedReferenceSequence->get($refbuild_id);
ok($ref_seq_build, 'human36 reference sequence build') or die;

my $tumor =  Genome::Config::get('test_inputs') . "/Genome-Model-Tools-DetectVariants2-Pindel/flank_tumor_sorted.bam";
my $normal = Genome::Config::get('test_inputs') . "/Genome-Model-Tools-DetectVariants2-Pindel/flank_normal_sorted.bam";

my $tmpbase = File::Temp::tempdir('PindelXXXXX', CLEANUP => 1, TMPDIR => 1);
my $tmpdir = "$tmpbase/output";

my $result_users = Genome::Test::Factory::SoftwareResult::User->setup_user_hash(
    reference_sequence_build => $ref_seq_build,
);

my $pindel = Genome::Model::Tools::DetectVariants2::Pindel->create(
    chromosome_list => [22],
    aligned_reads_input=>$tumor, 
    control_aligned_reads_input=>$normal,
    reference_build_id => $refbuild_id,
    output_directory => $tmpdir, 
    control_aligned_reads_sample => "TEST_NORMAL",
    aligned_reads_sample => "TEST",
    version => '0.5',
    result_users => $result_users,
);
ok($pindel, 'pindel command created');

ok($pindel->default_chromosomes_as_string =~ /^1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,X,Y,MT/, 'chromosomes are sorted correctly') || die;

$ENV{NO_LSF}=1;

$pindel->dump_status_messages(1);

my $rv = $pindel->execute;
is($rv, 1, 'Testing for successful execution.  Expecting 1.  Got: '.$rv);

my $output_indel_file = $pindel->output_directory . "/indels.hq.bed";

ok(-s $output_indel_file,'Testing success: Expecting a indel output file exists');

done_testing();
