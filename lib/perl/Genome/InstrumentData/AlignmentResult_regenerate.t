#!/usr/bin/env genome-perl

use strict;
use warnings FATAL => 'all';

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
};

use above "Genome";
use Test::More;
use Genome::Utility::Test;
use Genome::Test::Factory::Test qw(test_setup_object);
use Genome::Test::Factory::InstrumentData::AlignmentResult;
use Genome::Test::Factory::InstrumentData::MergedAlignmentResult;
use Genome::Test::Factory::DiskAllocation;
use Sub::Override;
use Test::MockObject::Extends;
use Sub::Install;
use Genome::Utility::Test qw(compare_ok);

my $pkg = 'Genome::InstrumentData::AlignmentResult';
use_ok($pkg) or die;

my $merge_id       = 'whole';
my $small_merge_id = 'small';
my $test_name      = 'AlignmentResult_regenerate.t unit test objects';
my $test_data_dir  = Genome::Utility::Test->data_dir_ok($pkg, '1');

my $reference_build_id = 1234;
my $ar1_instrument_data_id = 2894005119;
my $ar2_instrument_data_id = 2894005341;
my $per_lane_file_basename = 'all_sequences';
my $per_lane_bam = $per_lane_file_basename . '.bam';
my $per_lane_header = $per_lane_bam . '.header';
my $per_lane_flagstat = $per_lane_bam . '.flagstat';

my $ar_class         = 'Genome::Test::Factory::InstrumentData::AlignmentResult';
my $merge_class      = 'Genome::Test::Factory::InstrumentData::MergedAlignmentResult';
my $allocation_class = 'Genome::Test::Factory::DiskAllocation';

# We need to override this because get_merged_alignment_results only returns objects in the database... and these are mock objects
Sub::Install::install_sub({code => sub { my $self = shift; return @_; }, into => 'Genome::InstrumentData::AlignmentResult', as => 'filter_non_database_objects'});

my ($ar1, $ar2, $merged_result, $smaller_merged_result, $bad_merged_result) = get_test_alignment_results();

subtest 'get_merged_alignment_results' => sub {
    is_deeply([sort $ar1->get_merged_alignment_results], [sort($merged_result, $smaller_merged_result)], 'Got two merged alignment results for ar1');
    is_deeply([$ar2->get_merged_alignment_results], [$merged_result], 'Got one merged alignment result for ar2');
};


subtest 'get_unarchived_merged_alignment_results' => sub {
    is_deeply([sort $ar1->get_unarchived_merged_alignment_results], [sort($merged_result, $smaller_merged_result)], 'Got two unarchived merged results for ar1');
    is_deeply([$ar2->get_unarchived_merged_alignment_results], [$merged_result], 'Got one unarchived merged results for ar2');
    my $override = Sub::Override->new('Genome::Disk::Allocation::is_archived', sub {'1'});
    is_deeply([$ar1->get_unarchived_merged_alignment_results], [], 'Got 0 unarchived merged results for ar1');
    is_deeply([$ar2->get_unarchived_merged_alignment_results], [], 'Got 0 unarchived merged results for ar2');
    $override->restore;
};


subtest 'get_smallest_merged_alignment_result and get_merged_bam_to_revivify_per_lane_bam' => sub {
    is_deeply([$ar1->get_smallest_merged_alignment_result($ar1->get_merged_alignment_results)], [$smaller_merged_result], 'Got smallest merged result for ar1');
    is($ar1->get_merged_bam_to_revivify_per_lane_bam, File::Spec->join($smaller_merged_result->output_dir, $small_merge_id.'.bam'), 'Got smallest merged bam to revivify per lane bam for ar1');

    is_deeply([$ar2->get_smallest_merged_alignment_result($ar2->get_merged_alignment_results)], [$merged_result], 'Got smallest merged result for ar2');
    is($ar2->get_merged_bam_to_revivify_per_lane_bam, File::Spec->join($merged_result->output_dir, $merge_id.'.bam'), 'Got smallest merged result to revivify per lane bam for ar2');

    my $archived_allocation = Test::MockObject::Extends->new($smaller_merged_result->_disk_allocation);
    is($archived_allocation->owner, $smaller_merged_result, 'The new archived allocation has the smaller merged result as the owner');
    $archived_allocation->mock('is_archived', sub { 1 });

    is($ar1->get_merged_bam_to_revivify_per_lane_bam, File::Spec->join($merged_result->output_dir, $merge_id.'.bam'), 'We prefer the unarchived bam to the smaller one');
    $archived_allocation->unmock('is_archived');
};


subtest 'test per lane bam removal and recreation' => sub {
    my $ar2_header   = File::Spec->join($ar2->output_dir, $per_lane_header);
    Genome::Sys->copy_file(File::Spec->join($test_data_dir, 'ar2', $per_lane_header), $ar2_header);
    ok(-s $ar2_header, "$per_lane_header copied over ok");

    my $temp_allocation_dir = Genome::Sys->create_temp_directory();
    my $owner = Genome::Sys::User->get(username=>"apipe-tester");

    my $temp_allocation = $allocation_class->generate_obj(
        mount_path => $temp_allocation_dir,
        owner => $owner,
    );

    # The old and new paths should differ because the file has been revivified elsewhere
    my $old_path = File::Spec->join($ar2->output_dir, $per_lane_bam);
    my $new_path = $ar2->revivified_alignment_bam_file_paths(disk_allocation => $temp_allocation);
    isnt($old_path, $new_path, 'AR2 revivified_alignment_bam_file_paths exist and the path has changed');

    for my $extension qw(.bam .bam.bai) {
        my $base = $per_lane_file_basename.$extension;
        my $file = File::Spec->join($ar2->output_dir, $base);
        unlink $file;
        ok(!-s $file, "File $base removed ok as expected");
    }

    my @revivified_bams = $ar2->revivified_alignment_bam_file_paths(disk_allocation => $temp_allocation);
    is_deeply(\@revivified_bams, [File::Spec->join($temp_allocation_dir, $per_lane_bam)], 'AR2 revivified_alignment_bam_file_paths revivified as per lane bam ok');

    my $new_flagstat_file = Genome::Sys->create_temp_file_path;
    `samtools flagstat $revivified_bams[0] > $new_flagstat_file`;
    compare_ok($new_flagstat_file, File::Spec->join($ar2->output_dir, $per_lane_flagstat));
};


subtest 'test per lane bam removal and recreation with archiving' => sub {
    my $archived_allocation = Test::MockObject::Extends->new($merged_result->_disk_allocation);
    is($archived_allocation->owner, $merged_result, 'The new archived allocation has the merged result as the owner');
    $archived_allocation->mock('is_archived', sub { 1 });

    # Delete the merged bam
    my $merge_file = File::Spec->join($merged_result->output_dir, "$merge_id.bam");
    unlink($merge_file);
    ok(!-s $merge_file, "Merged bam is temporarily deleted");

    # Mock unarchive so it just copies the file back
    Sub::Install::install_sub({code => sub { unless (-s $merge_file) { Genome::Sys->copy_file(File::Spec->join($test_data_dir, $merge_id, "$merge_id.bam"), $merge_file); } },
            into => 'Genome::SoftwareResult', as => '_auto_unarchive'});

    # Unarchive the merged bam
    is($ar2->get_merged_bam_to_revivify_per_lane_bam, File::Spec->join($merged_result->output_dir, $merge_id.'.bam'), 'AR2 merged result successfully unarchived');
    ok(-s $merge_file, "Merged bam has been 'unarchived'");

    $archived_allocation->unmock('is_archived');
};


sub get_test_alignment_results {
    my %params = (
        reference_build_id => $reference_build_id,
        samtools_version   => 'r982',
        aligner_name       => 'bwa',
        picard_version     => '1.82',
    );

    # Set up alignment results
    my $ar1 = test_setup_object($ar_class, setup_object_args => [instrument_data_id => $ar1_instrument_data_id, %params] );
    is($ar1->instrument_data_id, $ar1_instrument_data_id, "AR1 has the proper instrument_data_id");

    my $ar2_dir = Genome::Sys->create_temp_directory();
    my $ar2 = test_setup_object( $ar_class, setup_object_args => [ instrument_data_id => $ar2_instrument_data_id, output_dir => $ar2_dir, %params ] );
    is($ar2->instrument_data_id, $ar2_instrument_data_id, "AR2 has the proper instrument_data_id");

    my $merge_dir = Genome::Sys->create_temp_directory();
    my $merged_result = test_setup_object($merge_class, setup_object_args => [id => $merge_id, output_dir => $merge_dir, %params]);
    Genome::SoftwareResult::Input->create(
        software_result => $merged_result,
        name => "instrument_data_id-0",
        value_id => "$ar1_instrument_data_id",
    );
    Genome::SoftwareResult::Input->create(
        software_result => $merged_result,
        name => "instrument_data_id-1",
        value_id => "$ar2_instrument_data_id",
    );

    my $small_merge_dir = Genome::Sys->create_temp_directory();
    my $smaller_merged_result = test_setup_object($merge_class, setup_object_args => [id => $small_merge_id, output_dir => $small_merge_dir, %params]);
    Genome::SoftwareResult::Input->create(
        software_result => $smaller_merged_result,
        name => "instrument_data_id-0",
        value_id => $ar1_instrument_data_id,
    );

    # The purpose of this 'bad_merged_result' is to add an object that should always be filtered out when searching for related objects
    # because it has a single parameter that is different (aligner_name)
    $params{aligner_name} = 'bwamem';
    my $bad_ar = test_setup_object($ar_class, setup_object_args => [instrument_data_id => $ar1_instrument_data_id, %params] );
    my $bad_merged_result = test_setup_object($merge_class, setup_object_args => [id => 'bad', %params]);
    Genome::SoftwareResult::Input->create(
        software_result => $bad_merged_result,
        name => "instrument_data_id-0",
        value_id => $ar1_instrument_data_id,
    );

    # need to manually calculte the lookup hash or get_with_lock will fail on mock objects
    map {$_->test_name($test_name); $_->recalculate_lookup_hash} ($ar1, $ar2, $bad_ar, $merged_result, $smaller_merged_result, $bad_merged_result);

    # Set up allocations
    class GenomeTest::Object{ };
    my $ar1_allocation = $allocation_class->generate_obj(
        owner => $ar1,
    );
    my $ar2_allocation = $allocation_class->generate_obj(
        owner      => $ar2, 
        mount_path => $ar2_dir,
    );
    my $merged_allocation = $allocation_class->generate_obj(
        owner      => $merged_result,
        mount_path => $merge_dir,
    );
    my $small_merged_allocation = $allocation_class->generate_obj(
        owner      => $smaller_merged_result,
        mount_path => $small_merge_dir,
    );
    my $bad_allocation = $allocation_class->generate_obj(
        owner => $bad_merged_result,
    );

    # Put test data in allocations
    for my $extension qw(.bam .bam.bai .bam.flagstat) { 
        my($ar2_base, $merge_base, $small_merge_base) = map{$_.$extension}($per_lane_file_basename, $merge_id, $small_merge_id);
        my $ar2_file         = File::Spec->join($ar2_allocation->absolute_path, $ar2_base);
        my $merge_file       = File::Spec->join($merged_allocation->absolute_path, $merge_base);
        my $small_merge_file = File::Spec->join($small_merged_allocation->absolute_path, $small_merge_base);

        Genome::Sys->copy_file(File::Spec->join($test_data_dir, 'ar2', $ar2_base), $ar2_file);
        ok(-s $ar2_file, "$ar2_base copied over ok");
        Genome::Sys->copy_file(File::Spec->join($test_data_dir, $merge_id, $merge_base), $merge_file);
        ok(-s $merge_file, "$merge_base copied over ok");
        Genome::Sys->copy_file(File::Spec->join($test_data_dir, $small_merge_id, $small_merge_base), $small_merge_file);
        ok(-s $small_merge_file, "$small_merge_base copied over ok");
    }

    # Validate test pre-conditions, these should always be true so it is not part of the unit test
    die 'instrument data id is incorrect for ar1' unless ($ar1->instrument_data_id eq $ar1_instrument_data_id);
    die 'instrument data id is incorrect for ar2' unless ($ar2->instrument_data_id eq $ar2_instrument_data_id);
    is_deeply([$merged_result->instrument_data_id], [$ar1_instrument_data_id, $ar2_instrument_data_id], "The merged result has the proper instrument_data_id");

    for my $result ($ar1, $ar2, $merged_result, $smaller_merged_result) {
        die 'test name is incorrect' unless $result->test_name eq $test_name;
    }

    die 'ar1 allocation is incorrect'    unless $ar1->_disk_allocation->id eq $ar1_allocation->id;
    die 'ar2 allocation is incorrect'    unless $ar2->_disk_allocation->id eq $ar2_allocation->id;
    die 'merged allocation is incorrect' unless $merged_result->_disk_allocation->id eq $merged_allocation->id;

    return ($ar1, $ar2, $merged_result, $smaller_merged_result, $bad_merged_result);
}

done_testing();
