package Genome::Model::DeNovoAssembly::Build::Assemble;

use strict;
use warnings;

use Genome;

class Genome::Model::DeNovoAssembly::Build::Assemble {
    is => 'Command::V2',
    has_input => [
        build => { 
            is => 'Genome::Model::Build::DeNovoAssembly',
            is_output => 1,
        },
        sx_results => {
            is => 'Genome::InstrumentData::SxResult',
            is_many => 1,
        },
    ],
};


sub execute {
    my $self = shift;

    my $build = $self->build;
    my $processing_profile = $build->processing_profile;

    $self->status_message('Assemble '.$build->__display_name__);

    my $assembler_class = $processing_profile->assembler_class;
    $self->status_message('Assembler class: '. $assembler_class);

    my %assembler_params = $build->assembler_params;
    $self->status_message('Assembler params: '.Data::Dumper::Dumper(\%assembler_params));

    my @sx_results = $self->sx_results;
    for my $sx_result ( @sx_results ) {
        $self->status_message('SX result: '.$sx_result->__display_name__);
    }

    my $before_assemble = $build->before_assemble(@sx_results);
    if ( not $before_assemble ) {
        $self->error_message('Failed to run before assemble for '.$build->__display_name__);
        return;
    }

    my $assemble = $assembler_class->create(%assembler_params);
    unless ($assemble) {
        $self->error_message("Failed to create de-novo-assemble");
        return;
    }
    $self->status_message("Created assembler for '$assembler_class'.\n");

    eval {
        unless ($assemble->execute) {
            $self->error_message("Failed to execute de-novo-assemble execute");
            return;
        }
        $self->status_message('Assemble...OK');
    };
    if ($@) {
        $self->error_message($@);
        die $@;
    }

    my $after_assemble = $build->after_assemble(@sx_results);
    if ( not $after_assemble ) {
        $self->error_message('Failed to run after assemble for '.$build->__display_name__);
        return;
    }

    return 1;
}

1;
