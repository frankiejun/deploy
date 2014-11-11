#!/usr/bin/perl
##author: frankiejun@gmail.com
##date:   2014-06-19
use DBI;
use Getopt::Std;
use Config::Tiny;
use Net::SSH::Perl;
use File::Basename;
use File::Path;
use File::Copy "mv";
use Cwd;
use String::Util qw(trim);
use Expect;
use POSIX qw(strftime);
use utf8;
binmode(STDOUT, ':encoding(utf8)');

use vars qw(%opt);

sub Usage {
	my $msg = "$0 usage: \n" .
		"-i   [指定配置文件, 必选]\n" .
		"-n   [指定要更新的svn工程代码,并进行ant编译打包]\n".
        "-v   [指定svn版本号,与-n搭配使用]\n".
        "-q   [只更新sql]\n".
        "-w   [只更新war包]\n".
        "-t   [只同步系统时间, 需配置root_pass选项]\n".
		"-s   [停掉远程tomcat工程]\n".
		"-r   [重启远程tomcat工程]\n".
		"-h   [帮助]\n";
    print $msg;
    exit;
}

sub non_blank_line {
    $f = shift;
    my $l; 
    do {
        $l = <$f>;
    }while(length(trim($l)) < 1);
    if($l =~ /CREATE OR REPLACE (.*$)/) {
        $l = $1;
    }
    return $l;
}
        

sub checksql {
    my $sql = shift;
    my $full_path = getcwd() ."/". $_ ;
    (my $pp_name = $sql) =~ s/(.+?)\.sql/$1/;
    my $owner = $config->{database}->{opt_user};
    my $sql_str = "select text from dba_source where name= upper('$pp_name') and owner= upper('$owner')";
    # print "full_path:$full_path\n";
    #print "sql-- $sql_str\n";
    my $sth = $dbh->prepare($sql_str);
    $sth->execute(); 
    open(FH, "< $full_path") or die $!;
    binmode(FH, ':encoding(utf8)');
    my $line = non_blank_line(\*FH);
    my $same = 0;
    while(my @arr = $sth->fetchrow_array) {
        if($arr[0] =~ /PROCEDURE/i) {
            $flag = 1;
            $line = <FH>;
			next;
        }
        if($flag == 1) {
            my $l = trim($arr[0]);
            my $r = trim($line);
            # print "[1]:$l\n";
            # print "[2]:$r\n";
            $line = <FH>;
			if($l ne $r) {
				print "diff between old and new PROCEDURE.\n";
				print "[1]:$l\n";
				print "[2]:$r\n";
				$same = 0;
				last;
			}
        }
        $same = 1;
    }
    $sth->finish();
    return $same;
}


sub update_sql {
    my $sql_dir = $config->{sql}->{dir};
    my @sql =` ls $sql_dir/*.sql | sort `;
    for(@sql){
        chomp;
        my $sql = basename($_);
        my $full_path = getcwd() ."/". $_ ;
        print "sql:$sql\n";
        print "full_path:$full_path\n";
        #procedure
        my $check = 0;
        if($sql !~ /^\d+/) {
            (my $pp_name = $sql) =~ s/(.+?)\.sql/$1/;
            print "backuping PROCEDURE $pp_name\n";
            get_pp($pp_name, ($config->{sql}->{backup_dir} or "./backup"));
            $check = 1;
		}
		my $c = "sqlplus -s $config->{database}->{opt_user}\/$config->{database}->{opt_password}\@".
		"$config->{database}->{dbid} \<\< EOF\n".
		"set echo off \n".
		"set heading off\n".
		"set sqlblanklines on\n".
		"set verify off\n".
		"\@$full_path \n\/  \n".
		"commit;\n".
		"EOF";

        system($c) == 0 or die "error for update sql";
        if($check) {
            if(checksql($sql) == 1) {
                print "check ...PROCEDURE updated successful\n"; 
            }else {
                die "check ...not update successful\n";
            }
        }
		my $done = "$sql_dir/done";
		if( ! -e $done ) {
		mkpath($done);
		}
		mv($full_path, "$done/$sql");	
    }
}

sub send_file {
    my ($ip, $usr, $pass, $file, $remote_path) = @_;
    print "ip:$ip|usr:$usr|pass:$pass|file:$file|remote_path:$remote_path\n";
    chomp($file);
    my $o = Expect->spawn("scp $file $usr\@$ip\:$remote_path") 
        or die "Cannot spawn $command: $!\n";
    $o->raw_pty(1);
    my ( $pos, $err, $match, $before, $after ) = $o->expect(10,    
        [ qr/\(yes\/no\)\?\s*$/ => sub { $o->send("yes\n"); exp_continue; } ],  
        [ qr/assword:\s*$/  => sub { $o->send("$pass\n") if defined $pass; } ],
		[ qr/100\%/ => sub { exp_continue; }]);

    $o->soft_close();
}

sub remote_call {
    my ($ip, $usr, $pass, $tomcat, $service_path, $local_shell, 
        $local_extent_shell, $remote_shell, $backup_dir, $war_file) = @_;
     
    if( defined($local_shell)) {
        my $work_shell = basename($local_shell);
        my $remote_path = $remote_shell ."/" . $work_shell;
        my $ssh = Net::SSH::Perl->new($ip);
        $ssh->login($usr, $pass);
        
        my $cmd = "/bin/bash $remote_path";
        die "must specify [tomcat] in cfg.ini\n" if not defined ($tomcat);
        $cmd .= " -t $tomcat";
        $cmd .= " -b $backup_dir " if defined $backup_dir;
        $cmd .= " -p $service_path " if defined $service_path;
        $cmd .= " -s \"$war_file\" " if defined $war_file;

        if ( defined $local_extent_shell) {
            my $extent_shell_name = basename($local_extent_shell);
            my $remote_extent_shell = $remote_shell . "/" . $extent_shell_name;
            $cmd .= " -x $remote_extent_shell > $remote_shell/tom.log 2>&1 ";
            #$cmd .= " -x $remote_extent_shell ";
        }else {
            $cmd .= " > $remote_shell/tom.log 2>&1 ";
        }
        print "remote call cmd:$cmd\n";
        my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
        # print "exitcode:$exit,msg:$stdout, err:$stderr\n";
        die "work shell error, msg:$stdout, err:$stderr\n" if $exit > 0 ;

    }
}

sub to_array {
	my $s = shift;
	my @a = split /,/, $s;
	for(@a) {
		$_ = trim($_);
	}
	return @a;
}

sub copy_files_to_remotehost {
    my $s = shift;

    my $ip = $config->{$s}->{ip};
    my $usr = $config->{$s}->{usr};
    my $pass = $config->{$s}->{pass};
    my $tomcat = $config->{$s}->{tomcat};
    my $war_dir = $config->{$s}->{war_dir};
    my $war_file = $config->{$s}->{war_file};
    my $service_path = $config->{$s}->{service_path};
    my $backup_flag = $config->{$s}->{backup_flag};
    my $backup_dir = $config->{$s}->{backup_dir};
    my $local_shell = $config->{$s}->{local_shell};
    my $remote_shell = $config->{$s}->{remote_shell};
    my $local_extent_shell = $config->{$s}->{local_extent_shell};
	my @war_files = to_array($war_file);

    if ($backup_flag != 1) {
        $backup_dir = undef;
    }
    print "copying file to remote host...\n";
    my $to_send_file = undef;
    if ( defined $war_file ) {
		for my $file (@war_files) {
			if ( defined $war_dir ) {
				$to_send_file .= " $war_dir/$file.war";
			}
		}
		$war_file =~ s/\s+//g;
    }elsif( defined $war_dir) {
        if ( -e $war_dir) {
            my @war_files = `ls $war_dir`;
            for(@war_files) {
                chomp;
                $to_send_file .= " $war_dir/" . $_;
            }
        }
    }else {
        die "no war file to be send[$to_send_file]\n";
    }
    print "sending file $to_send_file\n";
    send_file($ip, $usr, $pass, $to_send_file, $service_path);

    if(defined $local_shell and defined $remote_shell) {
        print "sending shell $local_shell\n";
        send_file($ip, $usr, $pass, $local_shell, $remote_shell);
    }
    if(defined  $local_extent_shell and defined $remote_shell) {
        print "sending extent shell $local_extent_shell\n";
        send_file($ip, $usr, $pass, $local_extent_shell, $remote_shell);
    }
    remote_call($ip, $usr, $pass, $tomcat, $service_path, $local_shell,
        $local_extent_shell, $remote_shell, $backup_dir, $war_file);
} 

sub update_war {
    my @sections = keys %$config;
    for(@sections) {
        if (/^to_.+?/) {
			print "$_\n";
            copy_files_to_remotehost($_);
        }
    }
}

sub do_sync_time {
    my $s = shift;
    my $ip = $config->{$s}->{ip};
    my $usr = $config->{$s}->{usr};
    my $pass = $config->{$s}->{pass};
    my $root_pass = $config->{$s}->{root_pass};
    
	if(!defined $root_pass) {
		return ;
	}
    print "$s sync time...\n";
    my $PROMPT  = '[\]\$\>\#]\s$';
    my $spawn = Expect->spawn("ssh $usr\@$ip");
	$spawn->log_file( "./ssh.log", "w" );
	$spawn->log_stdout(0);

    my $date = strftime("%Y-%m-%d %H:%M:%S", localtime(time));

    $spawn->expect(3, 
        [ qr/\(yes\/no\)\?\s*$/ => sub { $spawn->send("yes\n"); exp_continue; } ],
        [ qr/assword:\s*$/  => sub { $spawn->send("$pass\n") if defined $pass; } ],);

    $spawn->send("su -\n") if $spawn->expect(undef, '-re' => qr/\[$usr.*$/);
    sleep(1); #hard to match chinese,just wait.
    $spawn->send("$root_pass\n") if $spawn->expect(undef, '-re' => qr/([\x80-\xFF][\x80-\xFF])*/);
    $spawn->send("date -s \"$date\" \n") if $spawn->expect(undef, '-re' => qr/$PROMPT/);
    $spawn->send("exit\n") ;
    $spawn->send("exit\n") ;
    $spawn->soft_close();
}

sub synctime {
    my @sections = keys %$config;
    for(@sections) {
        if (/^to_.+?/) {
			print "$_\n";
            do_sync_time($_);
        }
    }
}

sub to_stop_war {
	my $s = shift;
	my $type = shift;
	my $ip = $config->{$s}->{ip};
	my $usr = $config->{$s}->{usr};
	my $pass = $config->{$s}->{pass};
    my $tomcat = $config->{$s}->{tomcat};
	my $local_shell = $config->{$s}->{local_shell};
	my $remote_shell = $config->{$s}->{remote_shell};

	if(defined $local_shell and defined $remote_shell) {
		print "sending shell $local_shell\n";
		send_file($ip, $usr, $pass, $local_shell, $remote_shell);
	}
	my $work_shell = basename($local_shell);
	my $remote_path = $remote_shell ."/" . $work_shell;
	my $cmd = "/bin/bash $remote_path";
	die "must specify [tomcat] in cfg.ini\n" if not defined ($tomcat);
	if($type == 1) {
		$cmd .= " -t $tomcat -o";
	}else{
		$cmd .= " -t $tomcat -r";
	}
	my $ssh = Net::SSH::Perl->new($ip);
	$ssh->login($usr, $pass);
	print "cmd:$cmd\n";
	my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
	print "$stdout\n";
	die "work shell error, msg:$stdout, err:$stderr\n" if $exit > 0 ;
}

sub stop_war {
    my @sections = keys %$config;
	my $flag = shift;
    for(@sections) {
        if (/^to_.+?/) {
			print "$_\n";
            to_stop_war($_, $flag);
        }
    }
}

sub create_xml {
	(my $tomcat_home, $basedir, $svnpath, $service, $xmlpath, $war) = @_;
	open(XML,  "> $xmlpath	") or die $!;
	print XML qq#<?xml version="1.0" encoding="UTF-8"?> \n#;
	print XML qq#<project basedir="$basedir" default="antwar"  name="$service">\n#;
	print XML qq#\t<target name="init" description="start">\n#;
	print XML qq#\t\t<property name="name" value="$service" />\n#;
	print XML qq#\t\t<property name="tomcat.home" value="$tomcat_home" /> \n#;
	my @dir = `ls $svnpath/$service`;
	foreach my $d(@dir) {
		chomp($d);
		next if ! -d "$svnpath/$service/$d";
		if($d =~ /WebContent/) {
			print XML qq#\t\t<property name="webapp" value="$svnpath/$service/WebContent"/> \n#;
		}elsif($d =~ /config/) {
			print XML qq#		<property name="config" value="$svnpath/$service/config"/>   \n#;
		}else {
			print XML qq#\t\t<property name="$d.src" value="$svnpath/$service/$d" />\n#;
		}
	}
	print XML qq#		<property name="lib" value="$svnpath/$service/WebContent/WEB-INF/lib"/>   \n#;
	print XML qq#		<property name="build.src" value="$basedir/build_$service/src"/>   \n#;
	print XML qq#		<property name="build.dest" value="$basedir/build_$service/WEB-INF/classes"/>   \n#;
	print XML qq#		<property name="buildwar.dest" value="$basedir/build_$service"/>   \n#;
#	print XML qq#		<property name="jar.dest" value="$basedir/build_$service/jar"/>   \n#;
	print XML qq#		<property name="war.dest" value="$war" />   \n#;
	print XML qq#		<path id="classpath">   \n#;
	print XML qq#			<fileset dir="\${tomcat.home}/lib">\n#;
	print XML qq#				<include name="*.jar"/>\n#;
	print XML qq#			</fileset>            \n#;
	print XML qq#			<fileset dir="\${lib}">   \n#;
	print XML qq#				<include name="*.jar"/>   \n#;
	print XML qq#			</fileset>   \n#;
	print XML qq#		</path>   \n#;
	print XML qq#	</target>          \n#;
	print XML qq#    <target name="prepare" depends="init" description="">  \n#;
	print XML qq#        <delete dir="\${buildwar.dest}"/> \n#;
	print XML qq#        <mkdir dir="\${build.src}"/>   \n#;
	print XML qq#        <mkdir dir="\${build.dest}"/>   \n#;
	print XML qq#        <mkdir dir="\${buildwar.dest}"/>   \n#;
#	print XML qq#        <mkdir dir="\${jar.dest}"/>   \n#;
	print XML qq#        <mkdir dir="\${war.dest}"/>   \n#;
	print XML qq#        <copy todir="\${build.src}">   \n#;
	foreach my $d(@dir) {
		chomp($d);
		next if ! -d "$svnpath/$service/$d";
		next if $d =~ /WebContent/;
		next if $d =~ /config/;
		print XML qq#\t\t\t<fileset dir="\${$d.src}"/> \n#;
	}
	print XML qq#        </copy>   \n#;
	print XML qq#        <copy todir="\${buildwar.dest}">   \n#;
	print XML qq#            <fileset dir="\${webapp}"/>   \n#;
	print XML qq#        </copy>   \n#;
	print XML qq#    </target>   \n#;
	print XML qq#    <target name="build" depends="prepare" description="build">   \n#;
	print XML qq#			<javac srcdir="\${build.src}" destdir="\${build.dest}" encoding="UTF-8"  includeantruntime="on">   \n#;
	print XML qq#				<classpath refid="classpath"/>   \n#;
	print XML qq#			</javac>   \n#;
	print XML qq#\n#;
	print XML qq#			<copy todir="\${build.dest}" preservelastmodified="true">\n#;
	print XML qq#				<fileset dir="\${build.src}">\n#;
	print XML qq#					<include name="**/*.xml"/>\n#;
	print XML qq#					<include name="**/*.properties"/>\n#;
	print XML qq#				</fileset>\n#;
	print XML qq#			</copy>\n#;
	print XML qq#			<copy todir="\${build.dest}">   \n#;
	print XML qq#				<fileset dir="\${config}">  \n#;
	print XML qq#				</fileset>   \n#;
	print XML qq#			</copy>   \n#;
	print XML qq#    </target>   \n#;
	print XML qq#       \n#;
	print XML qq#    <target name="antwar" depends="build" description="ant">   \n#;
	print XML qq#        <delete dir="\${build.src}"/>\n#;
	print XML qq#        <war warfile="\${war.dest}/$service.war" webxml="\${buildwar.dest}/WEB-INF/web.xml">   \n#;
	print XML qq#            <lib dir="\${buildwar.dest}/WEB-INF/lib"/>   \n#;
	print XML qq#            <classes dir="\${build.dest}"/>   \n#;
	print XML qq#            <fileset dir="\${buildwar.dest}"/>   \n#;
	print XML qq#        </war>   \n#;
	print XML qq#    </target>   \n#;
	print XML qq#       </project>\n#;
	close(XML);
}

sub to_pack {
	my $service = shift;
    my $ver = shift;
	my $user = $config->{svn}->{username};
	my $pass =$config->{svn}->{password};
	my $url = $config->{svn}->{url};
	my $svnpath = $config->{svn}->{svnpath};
	my $antpath = $config->{svn}->{antpath};
	my $basepath = $config->{svn}->{basepath};
	my $tomcat_home = $config->{svn}->{tomcat_home};
	my $war = $config->{svn}->{war};
	my $cmd = "svn co  --username $user --password $pass $url/$service  $svnpath/$service " .
    ($ver ne "" ? "-r $ver"  : "");
	print "$cmd\n";
    if(system($cmd) < 0) {
        print "update svn failed.";
        exit(-1);
    }
    my $xml = "$service"."_build.xml";
	if( !-e "$antpath/$xml" ) {
		create_xml($tomcat_home, $basepath, $svnpath, $service, "$antpath/$xml", $war);
	}
    $cmd = "$antpath/ant -f $antpath/$xml";
	print "$cmd\n";
    if(system($cmd) < 0) {
        print "compiling failed.";
        exit(-1);
    }
}

sub main {
    getopts("hi:n:v:qwtsr", \%opt) or Usage();

    if($opt{i}) {
        $config = Config::Tiny->new;
        $config = Config::Tiny->read($opt{i});
        if(! $config) {
            print Config::Tiny->errstr;
            exit(-1);
        }
        if($opt{q}) {
            print "update sql...\n";
            conn(); 
            update_sql();
            if($dhb) {
                $dbh->disconnect();
            }
		}elsif($opt{n}) {
			print "update $opt{n} svn and pack to war file...";
			to_pack($opt{n}, $opt{v});

		}elsif($opt{w}) {
            print "update war...\n";
            update_war();
		}elsif($opt{s}) {
			print "stop remote service...\n";
			stop_war(1);
		}elsif($opt{r}) {
			stop_war(2);
		}elsif($opt{t}) {
			synctime();
			exit(0);
        }else{
            print "update sql...\n";
            conn(); 
            update_sql();
            if($dhb) {
                $dbh->disconnect();
            }
            print "update war...\n";
            update_war();
        }
    }elsif($opt{h}) {
        Usage();
    }else{
        Usage();
    }

}

sub get_pp {
    my $pp = shift;
    my $bak = shift;
    my $owner = $config->{database}->{opt_user};
    my $sql = "select text from dba_source where name= upper('$pp') and owner= upper('$owner')";
    #print "sql-- $sql\n";
    my $sth = $dbh->prepare($sql);
    $sth->execute(); 
	if(! -e $bak ){
		mkpath($bak);
	}
    my $flag = 0;
    while(my @arr = $sth->fetchrow_array) {
		if($flag == 0) {
			open(OUT, "> $bak/$pp.sql") or die $!;
			binmode(OUT, ':encoding(utf8)');
			$flag = 1;
		}
        if($flag == 1) {
            print OUT $arr[0];
        }
    }
    $sth->finish();
	if($flag) {
		close(OUT);
	}
}

sub conn {
    $dbh= DBI->connect("DBI:Oracle:$config->{database}->{dbid}", 
        $config->{database}->{opt_user},
        $config->{database}->{opt_password}, { PrintError => 1})
    || die $DBI::errstr;
    print "connect ok\n";
}

main();
