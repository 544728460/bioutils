#!/usr/bin/perl

=head1 NAME

    10xreads2db.pl - Parse and import 10x reads into a MongoDB.

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Structure of V(D)J Enriched Library reads

=head3 Read 1

* Length:   150 bp

* Barcode:  16 bp
* UMI:      10 bp
* Switch:   13 bp
* Insert:   111 bp

=head3 Read 2

* Length:   150 bp

* Insert:   111 bp

=head2 Structure of 5' Gene Expression Library reads

=head3 Read 1

* Length:   26 bp

* Barcode:  16 bp
* UMI:      10 bp
* Insert:   NA

=head3 Read 2

* Length:   98 bp

* Insert:   98 bp

=head1 AUTHOR

    zeroliu-at-gmail-dot-com

=head1 VERSION

    0.0.1   - 2019-03-26

=cut

use 5.12.1;
use strict;
use warnings;

#use boolean;
use Getopt::Long;
use IO::Zlib;
use MongoDB;
#use MongoDB::Indexing;
use Smart::Comments;

#===========================================================
#
#                   Predefined Variables
#
#===========================================================

my $f_cb        = "737K-august-2016.txt";   # 10x cell barcode file
my $buffer_size = 10_000;   # Insert $buffer_size documents at one time
my $num_reads   = 0;        # Number of inserted reads
#my $found_cb    = 0;        # Number of reads with cell barcode

#===========================================================
#
#                   Main Program
#
#===========================================================

my ($fread1, $fread2, $db);

GetOptions(
    "i=s"   => \$fread1,
    "j=s"   => \$fread2,
    "d=s"   => \$db,
    "h"     => sub { die usage() },
);

unless ( $fread1 and $fread2 and $db) {
    warn "[ERROR] All arguments are required!\n\n";
    die usage();
}

# Load 10x cell barcodes into a hash
warn "[NOTE] Loading 10x cell barcodes ...\n";
my $rh_cbs  = load_cbs($f_cb);

# All cell barcodes into an array
my @cbs     = sort keys %{ $rh_cbs };

# Connect to local MongoDB w/ default port
my $mongo_client    = MongoDB->connect();

# Create database
my $mongo_db    = $mongo_client->get_database( $db );

# Create collection 'read'
my $coll_reads  = $mongo_db->get_collection( 'reads' );

# Rarse read files and insert into collection 'read'
warn "[NOTE] Working on read file: '", $fread1, "\n";
operate_reads($coll_reads, $fread1);

warn "[NOTE] Working on read file: '", $fread2, "\n";
operate_reads($coll_reads, $fread2);

# Create index
# Index for 'seq_id'
# $coll_reads->ensure_index({'seq_id' => 1});
# Index for cell barcode
# $coll_reads->ensure_index({'cb' => 1});
# Index for umi
# $coll_reads->ensure_index({'umi' => 1});
# Index for whether cell barcode exists
#$coll_reads->ensure_index({'cb_exist' => 1});
# Index for read #
# $coll_reads->ensure_index({'read_num' => 1});

my $indexes = $coll_reads->indexes;

my @idx_names  = $indexes->create_many(
    { keys => [ 'seq_id' => 1 ] },
    { keys => [ 'cb' => 1 ] },
    { keys => [ 'umi' => 1 ] },
    { keys => [ 'cb_exist' => 1 ] },
    { keys => [ 'read_num' => 1 ] },
);

say "Created indexes:\n", join "\n", @idx_names;

# Close connection
$mongo_client->disconnect;

exit 0;


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
Parse and import 10x reads into a MongoDB database.
Usage:
  10xreads2db.pl -i <R1> -j <R2> -d <db>
Args:
  -i <R1>:  Read1 file
  -j <R2>:  Read2 file
  -d <db>:  MongoDB name to be created.
Note:
  Both plain text and gzipped FASTQ format were supported.
EOS
}

=pod

  Name:     load_cbs
  Usage:    load_cbs($fcbs)
  Function: Load cell barcodes into a hash from cell barcode file.
  Args:     $fcbs:  A string for 10x cell barcode filename
  Returns:  A hash reference for all barcodes

=cut

sub load_cbs {
    my ($fcbs)  = @_;
    
    my %cbs;
    
    open my $fh_cbs, "<", $fcbs or
        die "[ERROR] Open 10x Cell Barcodes file '$fcbs' failed!\n$!\n";
        
    while (<$fh_cbs>) {
        next if /^#/;
        next if /^\s*$/;
        chomp;
        
        my $cb = $_;
        
        $cbs{$cb}++;
    }
        
    close $fh_cbs;
    
    return \%cbs;
}

=pod

  Name:     correct_cb
  Usage:    correct_cb($cb, $ra_cbs)
  Function: Correct cell barcodes with 1 mis-base
  Args:     $cb     A string, cell barcode to be corrected
            $ra_cbs An array reference, for all pre-defined barcodes
  Return:   A list of 2 items:
            1st item:   An integer, number of found cell barcodes.
                        0:  Not found, or w/ 2 or more mismatches
                        1:  Found only 1
                        2 or more:  Number of found barcodes
            2nd item:   A string, for cell barcode.
                        if 1st item == 1, corrected cell barcode
                        else, original barcode

=cut

sub correct_cb {
    my ($cb, $ra_cbs)   = @_;

    my $raw_cb  = $cb;

    my $num_mis = $cb =~ s/[^ACGT]/\./; # Convert cb to a regex

    ## $cb

    my $num_cbs = 0;    # Number of found cell barcodes

    if ($num_mis > 1) { # If mismatch bases number > 1
        return ($num_cbs, $raw_cb); # No cell barcode found,
                                    # return original cell barcode string
    }

    my @results = grep /$cb/, @{ $ra_cbs };

    ## @results

    $num_cbs    = scalar @results;

    # Not found or match more than once
    # return $num_res unless ($num_res = 1);   

    # return $results[0];

    if ($num_cbs == 1) {    # Found only one cell barcode
        my $corr_cb = $results[0];

        return ($num_cbs, $corr_cb);    # Return corrected cb
    }
    else {  # Otherwise, 0, 2 or more, return original cb
        return ($num_cbs, $raw_cb);
    }
}

=pod

  Name:     operate_reads
  Usage:    operate_reads($collection, $fread)
  Function: Parse read file and insert into record/document into 
            given collection.
  Args:     $collection:    A MongoDB::Collection instance
            $fread:         A filename
  Returns:  Number of inserted reads.

=cut

sub operate_reads {
    my ($coll, $freads) = @_;
    my $num_total_reads = 0;    # Number of total reads
    my $num_ins_reads   = 0;    # Number of inserted reads
    my $num_corr_cbs    = 0;    # Number of corrected barcode

    my $fh_reads;

    if ($freads =~ /\.(?:fq|fastq)$/) {    # A FASTQ file
        open $fh_reads, "<", $freads or
            die "[ERROR] Open reads file '$freads' failed!\n$!\n";
    }
    elsif ($freads =~ /\.(?:fq|fastq)\.gz$/) { # gzippd file
        #open $fh_reads, "<", "gzcat $freads |" or
        #    die "[ERROR] Open reads file '$freads' failed!\n$!\n";

        $fh_reads   = IO::Zlib->new($freads, 'rb') or
            die "[ERROR] Open reads file '$freads' failed!\n$!|n";
    }
    else {
        die "[ERROR] Unsupported file type for '$freads'!\n";
    }
    
    while ( <$fh_reads> ) {
        next if /^#/;
        next if /^\s*$/;
        chomp;
        
        if (/^@(\S+?)\s+(\S+?)$/) { # Seq ID line
            my $seq_id      = $1;
            my $seq_desc    = $2;

            $num_total_reads++;

            # Parse sequence description, get:
            # Read number:  $read_num
            # Sample index: $sample_idx
            my ($read_num, $is_filtered, $ctl_num, $sample_idx)
                = split /:/, $seq_desc;
            
            my $seq_str     = <$fh_reads>;
            chomp($seq_str);

            $seq_str        = uc $seq_str;  # Convert to uppercase

            my $read_len    = length($seq_str);
            
            my $opt_seq_id  = <$fh_reads>;
            chomp($opt_seq_id);
            
            unless ($opt_seq_id =~ /^\+/) {
                warn "[WARNING] May be not FASTQ format for '$seq_id'\n";
                next;
            }
                                
            my $seq_qual    = <$fh_reads>;
            chomp($seq_qual);

            if ($read_len >= 150) {  # V(D)J Enriched Library
                if ($read_num == 1) {   # Read #1
                    #$seq_str    =~ s/^N*//; # Remove possible leading N

                    my $cb      = substr $seq_str, 0, 16;
                    my $umi     = substr $seq_str, 16, 10;
                    my $switch  = substr $seq_str, 26, 13;
                    my $insert  = substr $seq_str, 39;

                    # $cb         = uc $cb;   # Convert to upper case

                    my $cb_exist=0;
                    my $corr_cb = '';

                    if ($cb =~ /[^ACGT]/) { # Other base except ACGT found
                        # say "Found misc base: '$cb'";

                        ($cb_exist, $corr_cb)
                            = correct_cb($cb, \@cbs);

                        $num_corr_cbs++ if ($cb_exist == 1);

# {{{
=pod
                        my $corr_cb = correct_cb($cb, \@cbs);

                        if ($corr_cb == 0) {
                            warn "[NOTE] Cell barcode '", $cb , 
                                "' not found\n";

                            $cb_exist   = 0;
                        }
                        elsif ($corr_cb > 1) {
                            warn "[NOTE] Found multiple matches for Cell ",
                                "barcode '", $cb, "'.\n";

                            $cb_exist   = $corr_cb;
                        }
                        else {
                            $cb         = $corr_cb; # use correction
                            $cb_exist   = 1;
                        }
=cut
# }}}
                    }
                    else {
                        (exists $rh_cbs->{$cb}) ? 
                            # $cb_exist = true : $cb_exist = false;
                            $cb_exist = 1 : $cb_exist = 0;
                    }
                    
                    $coll->insert_one( {
                        'seq_id'        => $seq_id,
                        'seq_desc'      => $seq_desc,
                        'seq'           => $seq_str,
                        'cell_barcode'  => $corr_cb,
                        'cb_exist'      => $cb_exist,
                        'umi'           => $umi,
                        'switch'        => $switch,
                        'insert'        => $insert,
                        'read_num'      => $read_num,
                        'sample_idx'    => $sample_idx,
                        'quality'       => $seq_qual,
                    } );

                    $num_ins_reads++;
                }
                elsif ($read_num == 2)  {   # Read #2
                    #$seq_str    =~ s/^N*//;

                    $coll->insert_one( {
                        'seq_id'        => $seq_id,
                        'seq_desc'      => $seq_desc,
                        'seq'           => $seq_str,
                        'insert'        => $seq_str,
                        'read_num'      => $read_num,
                        'sample_idx'    => $sample_idx,
                        'quality'       => $seq_qual,
                    } );

                    $num_ins_reads++;
                }
                else {
                    warn "[ERROR] Impossible read number: '$read_num'",
                        "for '$seq_id'\n";
                    next;
                }
            }
            elsif ($read_len >= 98 and $read_num == 2) {
                # 5' Gene Expression Library, Read #2
                #$seq_str    =~ s/^N*//;

                $coll->insert_one( {
                    'seq_id'        => $seq_id,
                    'seq_desc'      => $seq_desc,
                    'seq'           => $seq_str,
                    'insert'        => $seq_str,
                    'read_num'      => $read_num,
                    'sample_idx'    => $sample_idx,
                    'quality'       => $seq_qual,
                } );

                $num_ins_reads++;
            }
            elsif ($read_len >= 26 and $read_num == 1) {
                # 5' Gene Expression Library, Read #1
                # $seq_str    =~ s/^N*//;

                my $cb  = substr $seq_str, 0, 16;
                my $umi = substr $seq_str, 16;
                # There is NO switch Oligo available

                $cb             = uc $cb;

                my $cb_exist    = 0;
                my $corr_cb     = '';

                if ($cb =~ /[^ACGT]/) { # Other base except ACGT found
                    ($cb_exist, $corr_cb)
                        = correct_cb($cb, \@cbs);

                    $num_corr_cbs++ if ($cb_exist == 1);

# {{{
=pod
                    my $corr_cb = correct_cb($cb, \@cbs);

                    if ($corr_cb == 0) {
                        warn "[NOTE] Cell barcode '", $cb , 
                            "' not found\n";

                        $cb_exist   = 0;
                    }
                    elsif ($corr_cb > 1) {
                        warn "[NOTE] Found multiple matches for Cell ",
                            "barcode '", $cb, "'.\n";

                        $cb_exist   = $corr_cb;
                    }
                    else {
                        $cb         = $corr_cb; # use correction
                        $cb_exist   = 1;
                    }
=cut
# }}}
                }
                else {
                    (exists $rh_cbs->{$cb}) ? 
                        $cb_exist = 1 : $cb_exist = 0 ;
                }
 
                $coll->insert_one( {
                    'seq_id'        => $seq_id,
                    'seq_desc'      => $seq_desc,
                    'seq'           => $seq_str,
                    'cell_barcode'  => $corr_cb,
                    'cb_exist'      => $cb_exist,
                    'umi'           => $umi,
                    'insert'        => '',
                    'read_num'      => $read_num,
                    'sample_idx'    => $sample_idx,
                    'quality'       => $seq_qual,
                } );

                $num_ins_reads++;
            }
            else {
                warn "[WARNING] Unidentified read '$seq_id' ",
                    "in Read #", $read_num, "\n",
                    "with length: ", $read_len, "\n";
            }
        }
        else {
            next;
        }
        
    }
    
    close $fh_reads;

    say "Total reads number:\t", $num_total_reads;
    say "Inserted reads number:\t", $num_ins_reads;
    say "Corrected cell barcode:\t", $num_corr_cbs;

    return 1;
}
