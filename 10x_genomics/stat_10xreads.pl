#!/usr/bin/perl

=head1 NAME

    stat_10xreads.pl - Statistics 10x reads in given MongoDB database by
                       Cell Barcodes and UMI.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHOR

    zeroliu-at-gmail-dot-com

=head1 VERSION

    0.0.1   - 2019-04-04

=cut

use 5.12.1;
use strict;
use warnings;

use Getopt::Long;
use MongoDB;
use Smart::Comments;

#===========================================================
#
#                   Predefined Variables
#
#===========================================================

# The amount of time in milliseconds to wait for a new connection to 
# a server.
# Default: 10,000 ms
my $connect_timeout_ms  = 10_000;   # i.e., 10 s

# the amount of time in milliseconds to wait for a reply from the 
# server before issuing a network exception.
# Default: 30,000 ms
my $socket_timeout_ms   = 120_000;  # i.e., 120 s

#===========================================================
#
#                   Main Program
#
#===========================================================

my $host    = '127.0.0.1';
my $port    = '27017';

my ($db, $user, $pwd);

GetOptions(
    "d=s"       => \$db,
    "host=s"    => \$host,
    "port=s"    => \$port,
    "user=s"    => \$user,
    "pwd=s"     => \$pwd,
    "h"         => sub { die usage() },
);

unless ($db) {
    warn "[ERROR] Database name is required!\n";
    die usage();
}

# Connect to database
my $mongo_client    = MongoDB::MongoClient->new(
    host                => $host,
    port                => $port,
    connect_timeout_ms  => $connect_timeout_ms,
    socket_timeout_ms   => $socket_timeout_ms,
);

# Get given database
my $mongo_db  = $mongo_client->get_database( $db );

# Number of reads by Cell barcode
say "[NOTE] Statistics of Cell Barcodes ...";

my $cb_out  = $mongo_db->get_collection('reads')->aggregate(
    [
        { 
            '$match'    => { 'read_num' => 1 } 
        },
        { 
            '$group'    => {
                '_id'       => '$cell_barcode',
                'num_reads' => { '$sum' => 1 }
            }
        },
        {
            '$sort'     => { 'num_reads'=> -1 }
        }
    ]
);

# Output result to txt file.
my $f_out   = 'cb_stat.txt';

open my $fh_out, ">", $f_out or
    die "[ERROR] Create output file '$f_out' failed!\n$!\n";

say $fh_out join "\t", qw(Barcode Reads_number);

while (my $doc = $cb_out->next) {
    say $fh_out join "\t", ( $doc->{'_id'}, $doc->{'num_reads'} );
}

close $fh_out;

# Number of reads by cell barcide and UMI
say "[NOTE] Statistics of Cell Barcodes and UMI ...";

my $cb_umi_out  = $mongo_db->get_collection('reads')->aggregate(
    [
        { 
            '$match'    => { 'read_num' => 1 } 
        },
        {
            '$group'    => {
                '_id'       => {
                    'cb'        => '$cell_barcode',
                    'umi'       => '$umi'
                },
                'num_reads' => { '$sum' => 1 }
            },
        },
        {
            '$sort'     => { 'num_reads' => -1 }
        },
    ],  { allowDiskUse: true }
);

$f_out  = 'cb_umi_stat.txt';

open $fh_out, ">", $f_out or
    die "[ERROR] Create output file '$f_out' failed!\n$!\n";

say $fh_out join "\t", qw(Barcode UMI Reads_number);

while (my $doc = $cb_out->next) {
    ### $doc
    # say $fh_out join "\t", ( $doc->{'_id'}, $doc->{'num_reads'} );
}

close $fh_out;

#===========================================================
#
#                   Subroutines
#
#===========================================================

=pod

  Name:     usage
  Usage:    usage()
  Function: Display usage information
  Args:     None
  Returns:  None

=cut

sub usage {
    say << 'EOS';
Statistics 10x reads in given MongoDB database by Cell Barcodes and UMI.
Usage:
  stat_10xreads.pl -d <db> [--host <host>] [--port <port>] [--user <user>]
                        [--pwd <pwd>]
Arguments:
  -d <db>       MongoDB name.
  --host <host> Hostname or IP address to be connected. Optional.
                Default 127.0.0.1.
  --port <port> Port. Optional.
                Default 27017.
  --user <user> Username. Optional.
  --pwd <pwd>   Password. Optional.
EOS
}

=pod

  Name:     
  Usage:    
  Function: 
  Args:     
  Returns:  

=cut

