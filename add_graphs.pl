#!/usr/bin/perl -w
use strict ;
use Getopt::Long ;
use Data::Dumper;

use DBI; 
use DBD::mysql ; 

my %snmp_query_name_to_type_map = ( "SNMP - Interface Statistics" => "In/Out Bytes" ) ; 
my %snmp_query_name_to_graph_template_name_map =  ( "SNMP - Get Processor Information" => "Host MIB - CPU Utilization" , "SNMP - Interface Statistics" => "Interface - Traffic (bytes/sec)" , "SNMP - get ports" =>  "TCP extended stats" ) ; 
my $host = "";  # Host name supplied in the Arguement
my $cacti_cli_dir = ''  ;
my %h  ;
my %snmp_indexes =  ( "ioIndex" => "ioDescr"  , "ifIndex" => "ifDescr" , "hrProcessorFrwID" => "" , , "portIndex" => "portDescr" ) ;  
GetOptions ( \%h , 'host=s' , 'debug' , 'cacti_cli_dir' , 'dryrun' , 'host_template=s' , 'add_host' , 'graph_tree=s' , 'host_des=s', "graph_type=s" ) ;
my ( $debug   )  ;
my $dryrun = "" ; 
	if  ( $h{"debug"}  ) {
	  $debug = 1 ; 
	}
	
	if  ( ! exists($h{cacti_cli_dir} ) )
	{
	        $cacti_cli_dir = "/var/www/html/cacti/cli" ;
	}
	
	if ( ! exists($h{"host"}) ) { 
	  print " Please enter a host name \n \n Use --help to see the USAGE\n\n" ; 

	  exit 1 ; 
	}
   if ( exists ( $h{"dryrun"} ) ) {
      $dryrun = "echo" ; 
   }
if ( $h{"add_host"} && $h{"graph_type"} ) {
  print " add_host options and graph_type options can not be used together \n "; 
  exit ; 
}
if ( $h{"add_host"} ) { 
     if ( ! exists ( $h{"host_template"} ) )  { 
          print " Please enter host_template for adding host " ; 
          exit 1 ; 
     }
     my $host_des ; 
     if ( $h{"host_des"} ) { 
       $host_des = $h{"host_des"} ;
     } else { 
       $host_des = $h{host} ; 
     }
          
     add_host ( $h{"host_template"}  , "$h{host}" , "$cacti_cli_dir" , "$dryrun" , $h{"host_des"} ) ; 
}



my %configs ; 

load_configs ( "/var/www/html/cacti/cli/configs.conf" , \%configs ) ; 

## Database related stuff initialization ##

my $dsn = "dbi:mysql:$configs{\"database\"}:$configs{\"hostname\"}:$configs{\"port\"}" ;
my $DBIconnect = DBI->connect ($dsn, "$configs{\"username\"}" , "$configs{\"password\"}" ) or die "Unable to connect : $DBI::errstr\n" ; 
my %tree_hash ; 
## 


# print Dumper(\%configs) ; 
# print Dumper($DBIconnect) ; 
$host = $h{host}  ;
my $host_detail = `php $cacti_cli_dir/add_graphs.php --list-hosts | grep $host -i `  ;
if (! $host_detail ) {
  print "Host not found \n" ; 
  exit 1 ; 
}
my @host_detail = split /\s+/ , $host_detail ;
my %host ;
my @detail = qw/id  hostname template description/ ;
@host{@detail} = @host_detail ;

if ( $h{"graph_tree"} ) { 
     find_graph_trees($DBIconnect , \%tree_hash ) ; 
     my $tree_id = find_tree_exists ( "$h{\"graph_tree\"}" , \%tree_hash ) ; 
     if ( ! defined ( $tree_id ) ) { 
          add_graph_tree( "$h{\"graph_tree\"}" , "$cacti_cli_dir" , "manual" ) ; 
          find_graph_trees($DBIconnect , \%tree_hash ) ; 
     }
     $tree_id = find_tree_exists ( "$h{\"graph_tree\"}" , \%tree_hash ) ;
     print " host id : $host{\"id\"} \n " ;
     add_node_to_tree ( "node" , "host" , $tree_id , "$host{\"id\"}" , "1"  , "$cacti_cli_dir" , $DBIconnect ) ; 
}

if ( $h{"graph_type"} ) { 
  add_graph_templates ( $host{"id"} , $h{"graph_type"} ) ;
}



# print Dumper(\%tree_hash) ; 

my ( %host_graph_templates , %host_input_fields , %all_snmp_queries , %snmp_query_types , %host_snmp_fields , %host_snmp_values ) ;

# Temparary Variables

my ( @tmp_var , @tmp_var2 , $tmp_var , $tmp_var2 ) ; 

#Script variables 
@tmp_var = `php $cacti_cli_dir/add_graphs.php --list-graph-templates --host-template-id=$host{"template"} ` ;

foreach my $key ( @tmp_var ) {
        if (    $key =~ /^(\d+)\s+(.*)$/ ) {
                my $graph_id  = $1 ; 
                my $graph_name = $2 ; 
                chomp($graph_id) ; 
                chomp($graph_name ) ; 
                $host_graph_templates{$graph_id} = "$graph_name" ;
        }
}

########################## TEST CODE ###########################
if ( $h{"graph_type"} ) { 
  my $array_ids = `perl $cacti_cli_dir/update_graph_mapping.pl $h{"graph_type"}` ;
    print " couldn't find ids for graph type : $h{\"graph_type\"} \n  " if ( ! $array_ids ) ;
      my @ids = split /\s/ , $array_ids ;
        foreach my $id ( @ids )  {
          $host_graph_templates{$id} = $h{"graph_type"} ;
        }
}
#########################################################


if ( $debug  ) {  
   print "## Host graph templates : $host{\"hostname\"} \n" ; 
   print Dumper(\%host_graph_templates) ;
}

my @graph_templates = sort (  keys (%host_graph_templates) ) ;


# Finding out input feilds for each graph templates


@tmp_var = `php $cacti_cli_dir/add_graphs.php --list-snmp-queries` ;

foreach my $key ( @tmp_var ) {
   if (  $key =~ /^(\d+)\s+(.*)$/ ) {
         my $tmp_snmp_id = $1 ; 
         chomp($tmp_snmp_id) ; 
         my $tmp_snmp_name ; 
         $tmp_snmp_name = $2 ; 
         chomp($tmp_snmp_name) ; 
         $all_snmp_queries{$tmp_snmp_id} = "$tmp_snmp_name" ;
            }

}
foreach $tmp_var ( keys %all_snmp_queries ) {
   @tmp_var = `php $cacti_cli_dir/add_graphs.php --list-query-types --snmp-query-id=$tmp_var` ;
   @tmp_var2 = `php $cacti_cli_dir/add_graphs.php --list-snmp-fields --host-id=$host{id} --snmp-query-id=$tmp_var` ;
   $snmp_query_types{"$tmp_var"} = {} ;
   foreach $tmp_var2 ( @tmp_var ) {
      if (  $tmp_var2 =~ /^(\d+)\s+(.*)$/ ) {
         my $match1 = $1 ; 
         my $match2 = $2 ; 
         chomp ($match1) ; chomp($match2) ; 
         $snmp_query_types{"$tmp_var"}->{"$match1"} = "$match2" ;
      }
   }
   foreach $tmp_var2 ( @tmp_var2 ) {
      if ( $tmp_var2 !~ /(^Known.*)|(^\n)/ ) {
         if ( $tmp_var2 =~ /^(\w+.*)$/ ) {
            if ( ! defined $host_snmp_fields{$tmp_var} ) {
               $host_snmp_fields{$tmp_var}  = {} ; 
            }
            my @tmp_var3 = `php $cacti_cli_dir/add_graphs.php --list-snmp-values  --host-id=$host{id} --snmp-query-id=$tmp_var --snmp-field=$tmp_var2`  ; 

            my @snmp_values ; 
            foreach my  $tmp_var3 ( @tmp_var3 ) {
              if ( $tmp_var3 !~ /(^Known.*)|(^\n)/ ) {
                chomp($tmp_var3) ; 
               push @snmp_values , $tmp_var3 ; 
              }
            }
            chomp($tmp_var2) ; 
            $host_snmp_fields{$tmp_var}{$tmp_var2} = [ @snmp_values ] ; 
         }
      }
   }

   my @query_id_snmp =  () ; 
   my $query_id_snmp ; 
   foreach $tmp_var2 ( @tmp_var ) {
      if (  $tmp_var2 =~ /^(\d+)\s+(.*)$/ ) {
        my $match2 = $1 ; 
        chomp($match2) ; 
        push @query_id_snmp , $match2 ; 

      }
   }
   if ( scalar (@query_id_snmp) > 1 ) { 
      foreach my $snmp_query_name ( keys %snmp_query_name_to_type_map ) { 
        if ( $all_snmp_queries{$tmp_var} =~ /$snmp_query_name/i ) {
          foreach my $snmp_query_id ( keys %snmp_query_types ) { 
            foreach my $snmp_query_type_id ( keys %{$snmp_query_types{$snmp_query_id}} ) { 
	            my $tmp_string1 = "$snmp_query_name_to_type_map{$snmp_query_name}" ; 
	            my $tmp_string2 = "$snmp_query_types{$snmp_query_id}{$snmp_query_type_id}" ; 
	            $tmp_string1 =~ s/\W//g ; 
	            $tmp_string2 =~ s/\W//g ; 
	            if ( $tmp_string1 =~ /$tmp_string2/i ) { 
	              $query_id_snmp = $snmp_query_type_id ;
               }
            }
          }
        }
      }
   }
   else { 
     $query_id_snmp =  $query_id_snmp[0]  ; 
   }
   $host_snmp_fields{$tmp_var}->{"snmp_query_id"} =  $query_id_snmp ; 
}

print "## SNMP QUERY TYPE ID's FOR SNMP QUERY ID's  \n" . Dumper(\%snmp_query_types) if ( $debug ) ;

my $graph_type = "ds" ; 
foreach $tmp_var ( keys %host_graph_templates ) {
  foreach $tmp_var2 ( keys %snmp_query_types) { 
    foreach my $tmp_var3 ( keys %{$snmp_query_types{$tmp_var2}} ) {
      if ( "$host_graph_templates{$tmp_var}" eq "$snmp_query_types{$tmp_var2}{$tmp_var3}" ) {
      $host_snmp_fields{$tmp_var2}->{"grabh_template"} = "$tmp_var" ; 
      }
    }
  }
}
foreach $tmp_var ( keys %host_snmp_fields ) {
  if ( ! ( defined ( $host_snmp_fields{$tmp_var}->{"grabh_template"} ) ) ) {
      foreach my $snmp_query_name ( keys %snmp_query_name_to_graph_template_name_map ) { 
        if ( $all_snmp_queries{$tmp_var} =~ /$snmp_query_name/i ) { 
          foreach my $snmp_host_graph_template_id ( keys %host_graph_templates ) { 
            my $tmp_string1 = "$host_graph_templates{\"$snmp_host_graph_template_id\"}" ; 
            my $tmp_string2 = "$snmp_query_name_to_graph_template_name_map{\"$snmp_query_name\"}" ; 
            $tmp_string1 =~ s/\W//g ; 
            $tmp_string2 =~ s/\W//g;

            if ( $tmp_string1 =~ /$tmp_string2/i ) { 
              $host_snmp_fields{$tmp_var}->{"grabh_template"} = $snmp_host_graph_template_id  ; 
            }
          }
        }
      }
  }
}

      
   
print "## SNMP FIELDS FOR HOST $host{id}  with SNMP QUERY ID's \n " . Dumper(\%host_snmp_fields) if ($debug ) ;
my $snmp_id ;
my $index_value ; 
foreach $snmp_id ( keys %host_snmp_fields ) { 
  if (  exists (  $host_snmp_fields{$snmp_id}{"grabh_template"} ) ) {
    my $snmp_query_type_id = $host_snmp_fields{"snmp_query_id"} ; 
    foreach my $snmp_fields ( keys %{ $host_snmp_fields{$snmp_id} } ) { 
      foreach my $snmp_index ( keys %snmp_indexes ) { 
        my $snmp_index_host = scalar ( $host_snmp_fields{$snmp_id}{$snmp_fields} ) ; 
        if ( $snmp_fields =~ /$snmp_index/i ) {
          my $index = "$snmp_indexes{$snmp_index}" ; 
          if ( ! ( $snmp_indexes{"$snmp_index"} eq ""  ) ) {
            my $index_values  = $snmp_indexes{$snmp_index} ; 
            foreach  $index_value ( @{$host_snmp_fields{$snmp_id}{$index_values}} ) { 
               system("$dryrun php $cacti_cli_dir/add_graphs.php --graph-type=ds  --host-id=\"$host{\"id\"}\" --snmp-query-id=\"$snmp_id\"  --snmp-field=\"$index_values\" --graph-template-id=\"$host_snmp_fields{$snmp_id}{'grabh_template'}\"  --snmp-query-type-id=\"$host_snmp_fields{$snmp_id}{snmp_query_id}\"  --snmp-value=\"$index_value\" \n");
            }
          }
          else {
            foreach my  $host_fields (  @{$host_snmp_fields{$snmp_id}{$snmp_index}} ) { 
              system ( " $dryrun php $cacti_cli_dir/add_graphs.php  --graph-type=ds  --host-id=\"$host{\"id\"}\" --snmp-query-id=\"$snmp_id\"  --snmp-field=\"$snmp_index\" --graph-template-id=\"$host_snmp_fields{$snmp_id}{\"grabh_template\"}\"  --snmp-query-type-id=\"$host_snmp_fields{$snmp_id}{snmp_query_id}\" --snmp-value=\"$host_fields\" ") ; 
            }
          }
        }
      }
    }
  }
}
foreach my $graph_template ( keys %host_graph_templates ) { 
  my $match = 0 ; 
  foreach my $snmp_id ( keys %host_snmp_fields ) { 
    if ( defined ( $host_snmp_fields{$snmp_id}{"grabh_template"}  ) ) {
    if ( ( "$host_snmp_fields{$snmp_id}{'grabh_template'}" eq "$graph_template" ) && $match == 0 )   {
      $match = 1 ; 
      last ; 
    }
    }
  }
  
  system ( "$dryrun php $cacti_cli_dir/add_graphs.php  --graph-type=cg  --graph-template-id=$graph_template --host-id=$host{\"id\"} " ) if ( $match == 0 ) ; 
}


sub add_host {
     my $host_template = shift ; 
     my $host = shift ; 
     my $cacti_cli_dir = shift ;
     my $dryrun = shift ; 
     my $des = shift ; 
# Adding host to cacti if --add-host option is present 
     system ("$dryrun php $cacti_cli_dir/add_device.php --description=\"$des\" --ip=$host --template=$host_template ") ; 
}

sub add_host_to_tree { 
     my $graph_tree = shift ; 
     my $host = shift ;
     my $cacti_cli_dir = shift ;
     my $dryrun = shift ;
}

sub load_configs { 
     my $config_file = shift ; 
     my $conf = shift ; 
     my $FILE ;
     open ( $FILE ,  "$config_file"  ) ; 
     while ( <$FILE> ) {
          my ($key , $value ) = split(":" , $_ ) ; 
          $key =~ s/\s//g ; 
          $value =~ s/\s//g ; 
          $conf->{"$key"} = "$value" ; 
     }
}
sub find_graph_trees { 
     my $dbhandler = shift ; 
     my $tree_hash = shift ; 
     my $query = "select * from graph_tree" ; 
     my $query_handle = $dbhandler->prepare($query) ; 
     $query_handle->execute ; 
     my ($id,$sort_type,$name) ; 
     $query_handle->bind_columns(undef , \$id , \$sort_type , \$name ) ; 
     while ( $query_handle->fetch() ) { 
       print "$id , $sort_type , $name \n" ; 
       $tree_hash->{"$name"} = "$id" ;
     }
}

sub find_tree_exists { 
  my $tree = shift ; 
  my $all_trees = shift ; 
  my $id ; 
  foreach my $tree_name ( keys %{$all_trees} ) {
    if ( $tree_name =~ /$tree/i ) {
      $id = $all_trees->{"$tree_name"} ; 
    }
  }
  return $id ; 
}

sub add_graph_tree {
  my $name = shift ; 
  my $cacti_cli_dir = shift ; 
  my $sort_method = shift ; 
  system ("php $cacti_cli_dir/add_tree.php --type=tree --name=$name --sort-method=$sort_method") ; 
}

sub add_node_to_tree  {
  my $node = shift ; 
  my $host = shift ; 
  my $tree_id = shift ; 
  my $host_id = shift ; 
  my $host_group_style = shift ; 
  my $cacti_cli_dir = shift ; 
  my $dbhandler = shift ; 
  my $query = "select host_id from graph_tree_items where graph_tree_id=$tree_id" ; 
  my $query_handle = $dbhandler->prepare($query) ; 
  $query_handle->execute ; 
  my $hostid ; 
  $query_handle->bind_columns(undef , \$hostid ) ; 
  while ( $query_handle->fetch() ) {
    if ( $hostid =~ /$host_id/i ) { 
      print "Not adding node existing $host_id in $tree_id \n\n " ; 
      return ; 
    }
  }
  system ( "php $cacti_cli_dir/add_tree.php --type=$node --node-type=$host --tree-id=$tree_id --host-id=\"$host_id\" --host-group-style=$host_group_style" ) ; 
}

sub add_graph_templates { 
  my $host_id = shift ; 
  my $graph_type = shift ; 
  my $array_ids = `perl $cacti_cli_dir/update_graph_mapping.pl $graph_type` ; 
  print " couldn't find ids for graph type : $graph_type \n  " if ( ! $array_ids ) ; 
  my @ids = split /\s/ , $array_ids ; 
  foreach my $id ( @ids )  { 
    print " Adding  graph template id : $id for graph type : $graph_type \n" ;
    system ( "php $cacti_cli_dir/add_graph_template.php  --host-id=$host_id --graph-template-id=$id" ) ; 
  }
}


