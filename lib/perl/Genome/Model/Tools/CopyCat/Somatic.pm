package Genome::Model::Tools::CopyCat::Somatic;

use strict;
use Genome;
use IO::File;
use File::Basename;
use warnings;
require Genome::Sys;
use FileHandle;
use File::Spec;

class Genome::Model::Tools::CopyCat::Somatic{
    is => 'Command',
    has => [        
        normal_window_file => {
            is => 'String',
            is_optional => 0,
            is_input => 1,
            doc => 'normal window file to get reads from (output of gmt bam-window)',
        },
        tumor_window_file => {
            is => 'String',
            is_optional => 0,
            is_input => 1,
            doc => 'tumor window file to get reads from (output of gmt bam-window)',
        },
        output_directory => {
            is => 'String',
            is_optional => 0,
            is_input => 1,
            is_output => 1,
            doc =>'path to the output directory',
        },
        per_library => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 1,
            doc =>'do normalization on a per-library basis',
        },
        per_read_length => {
            is => 'Boolean',
            is_optional => 1,
            is_input => 1,
            default => 1,
            doc =>'do normalization on a per-read-length basis',
        },
        annotation_data_id => {
            is => 'String',
            is_optional => 0,
            is_input => 1,
            doc => 'Run "gmt copy-cat list" to see available versions (and be aware that the list command takes like 3 minutes to complete',
        },
        tumor_samtools_file => {
            is => 'String',
            is_input => 1,
            is_optional => 1,
            doc =>'samtools file which will be used to find het snp sites and id copy-number neutral regions in tumor',
        },
        normal_samtools_file => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            doc =>'samtools file which will be used to find het snp sites and id copy-number neutral regions in normal',
        },
        samtools_file_format => {
            is => 'String',
            is_optional => 1,
            is_input => 1,
            doc =>'format of the samtools files. Options are "10colPileup" and "VCF". If anything else is specified, it will attempt to infer the type from the header of the file',
            default => "unknown",
        },
        processors => {
            is => 'Integer',
            is_optional => 1,
            default => 1,
            doc => "set the number of processors that the parallel steps will use",
        },
        dump_bins => {
            is => 'Boolean',
            is_optional => 1,
            default => 1,
            doc => "write out the corrected bins to a file (pre-segmentation)"
        },
        do_gc_correction => {
            is => 'Boolean',
            is_optional => 1,
            default => 1,
            doc => "use loess correction to account for gc-bias",
        },
        min_width => {
            is => 'Integer',
            is_optional => 1,
            default => 3,
            doc => "the minimum number of consecutive windows required in a segment",
        },
        min_mapability => {
            is => 'Number',
            is_optional => 1,
            default => 0.60,
            doc => "the minimum mapability needed to include a window",
        },
        tumor_purity => {
            is => 'Number',
            is_optional => 1,
            default => 1,
            doc => "the estimated fraction of the tumor sample composed of tumor cells (as opposed to normal admixture)",
        },
    ],
    has_param => [
        lsf_resource => {
            default_value => "-M 8000000 -R 'select[mem>8000] rusage[mem=8000]'",
        },
    ],
};

sub help_brief {
    "Takes two files generated by bam-window. Runs the R copyCat package to correct the data for GC content bias and segment it into regions of copy number loss and gain."
}

sub help_detail {
    "Takes two files generated by bam-window. Runs the R copyCat package to correct the data for GC content bias and segment it into regions of copy number loss and gain."
}

sub execute {
    my $self = shift;

    my $tumor_window_file = $self->tumor_window_file;
    my $normal_window_file = $self->normal_window_file;
    my $output_directory = $self->output_directory;
    my $per_lib = $self->per_library;
    my $per_read_length = $self->per_read_length;
    my $tumor_samtools_file = $self->tumor_samtools_file;
    my $normal_samtools_file = $self->normal_samtools_file;
    my $processors = $self->processors;
    my $dump_bins = $self->dump_bins;
    my $min_width = $self->min_width;
    my $min_mapability = $self->min_mapability;
    my $tumor_purity = $self->tumor_purity;


    #get annotation directory
    my $annotation_sr = Genome::Model::Tools::CopyCat::AnnotationData->get($self->annotation_data_id);
    unless ($annotation_sr) {
        die $self->error_message("Couldn't find an annotation data set for ID %s", $self->annotation_data_id);
    }
    my $annotation_directory = $annotation_sr->annotation_data_path;

    #resolve relative paths to full path - makes parsing the R file easier if you want tweaks
    $output_directory = File::Spec->rel2abs($output_directory);
    unless(-d $output_directory){
        `mkdir -p $output_directory`;
    }
    $annotation_directory = File::Spec->rel2abs($annotation_directory);

    if(defined($tumor_samtools_file)){
        $tumor_samtools_file = File::Spec->rel2abs($tumor_samtools_file);
    }
    if(defined($normal_samtools_file)){
        $normal_samtools_file = File::Spec->rel2abs($normal_samtools_file);
    }

    if(defined($normal_window_file)){
        $normal_window_file = File::Spec->rel2abs($normal_window_file);
    }
    if(defined($tumor_window_file)){
        $tumor_window_file = File::Spec->rel2abs($tumor_window_file);
    }
    
    #make sure the files exist
    unless(-e $normal_window_file){
        die("file not found $normal_window_file");
    }
    unless(-e $tumor_window_file){
        die("file not found $tumor_window_file");
    }
    if(defined($tumor_samtools_file)){
        if(-e $tumor_samtools_file){
            $tumor_samtools_file = "\"$tumor_samtools_file\"";
        } else {
            die("file not found $tumor_samtools_file");
        }
    } else {
        $tumor_samtools_file = "NULL";
    }
    if(defined($normal_samtools_file)){
        if(-e $normal_samtools_file){
            $normal_samtools_file = "\"$normal_samtools_file\"";
        } else {
            die("file not found $normal_samtools_file");
        }
    } else {
        $normal_samtools_file = "NULL";
    }

    if($dump_bins){
        $dump_bins="TRUE";
    } else {
        $dump_bins="FALSE";
    }

    my $gcCorr="TRUE";
    if(!($self->do_gc_correction)){
        $gcCorr="FALSE";
    }

    #open the r file
    open(my $RFILE, ">$output_directory/run.R") || die "Can't open R file for writing.\n";
    print $RFILE "options(error = \n","   function() {\n", "      traceback(2)\n","      quit(\"no\",status=1)\n","   }",")\n";      
    print $RFILE "library(copyCat)\n";

    print $RFILE "runPairedSampleAnalysis(annotationDirectory=\"$annotation_directory\",\n";
    print $RFILE "                        outputDirectory=\"$output_directory\",\n";
    print $RFILE "                        normal=\"$normal_window_file\",\n";
    print $RFILE "                        tumor=\"$tumor_window_file\",\n";
    print $RFILE "                        inputType=\"bins\",\n";
    print $RFILE "                        maxCores=$processors,\n";
    print $RFILE "                        binSize=0,\n";
    print $RFILE "                        perLibrary=$per_lib,\n";
    print $RFILE "                        perReadLength=$per_read_length,\n";
    print $RFILE "                        verbose=TRUE,\n";
    print $RFILE "                        minWidth=$min_width,\n";
    print $RFILE "                        minMapability=$min_mapability,\n";
    print $RFILE "                        dumpBins=$dump_bins,\n";
    print $RFILE "                        doGcCorrection=$gcCorr,\n";
    print $RFILE "                        samtoolsFileFormat=\"" . $self->samtools_file_format ."\",\n";
    print $RFILE "                        purity=" . $tumor_purity .",\n";
    print $RFILE "                        normalSamtoolsFile=$normal_samtools_file,\n";
    print $RFILE "                        tumorSamtoolsFile=$tumor_samtools_file)\n";

    close($RFILE);

#print all of this to STDERR for debugging:
    print STDERR "Calling copy cat with params:\n";
    print STDERR "runPairedSampleAnalysis(annotationDirectory=\"$annotation_directory\",\n";
    print STDERR "                        outputDirectory=\"$output_directory\",\n";
    print STDERR "                        normal=\"$normal_window_file\",\n";
    print STDERR "                        tumor=\"$tumor_window_file\",\n";
    print STDERR "                        inputType=\"bins\",\n";
    print STDERR "                        maxCores=$processors,\n";
    print STDERR "                        binSize=0,\n";
    print STDERR "                        perLibrary=$per_lib,\n";
    print STDERR "                        perReadLength=$per_read_length,\n";
    print STDERR "                        verbose=TRUE,\n";
    print STDERR "                        minWidth=$min_width,\n";
    print STDERR "                        minMapability=$min_mapability,\n";
    print STDERR "                        dumpBins=$dump_bins,\n";
    print STDERR "                        doGcCorrection=$gcCorr,\n";
    print STDERR "                        samtoolsFileFormat=\"" . $self->samtools_file_format ."\",\n";
    print STDERR "                        purity=" . $tumor_purity .",\n";
    print STDERR "                        normalSamtoolsFile=$normal_samtools_file,\n";
    print STDERR "                        tumorSamtoolsFile=$tumor_samtools_file)\n";

    #drop into the output directory to make running the R script easier
    my $cmd = "Rscript $output_directory/run.R";
    my $return = Genome::Sys->shellcmd(
        cmd => "$cmd",
        );
    unless($return) {
        $self->error_message("Failed to execute: Returned $return");
        die $self->error_message;
    }
    return $return;
}

1;
