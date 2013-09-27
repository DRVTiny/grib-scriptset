#!/usr/bin/perl
use strict;
use File::Basename;
use Getopt::Compact;
use MIME::Lite;

my $pthFile;
my $emailTO;
my $emailFROM='ak@namos.ru';
my $txtSubject="You've got a file";

my $ret_ = new Getopt::Compact
 ( name => 'mailfile.pl', version => '0.01', modes => [qw(debug)],
   struct => [ [ [qw(f file)],      qq(specify a file to send as an attachment to your message), '=s', \$pthFile    ],
               [ [qw(d rcpt_to)],   qq(recipient email aka to whom to send the file),            '=s', \$emailTO    ],
               [ [qw(s mail_from)], qq(sender email),                                            '=s', \$emailFROM  ],
               [ [qw(T subject)],   qq(mail subject),                                            '=s', \$txtSubject ]
             ]
 );

my $opts=$ret_->opts;

( -f $pthFile ) || die "No such file $pthFile";

print "file=$pthFile, from=$emailFROM, to=$emailTO\n";


### Create a new multipart message:
my $msg = MIME::Lite->new(
             From    => $emailFROM,
             To      => $emailTO,
             Subject => $txtSubject,
             Type    =>'multipart/mixed'
);

### Add parts (each "attach" has same arguments as "new"):
$msg->attach(Type     => 'TEXT',
             Data     => 'See attachment'
             );
             
$msg->attach(Type     =>'application/octet-stream',
             Path     => $pthFile,
             Filename => basename($pthFile),
             Disposition => 'attachment'
             );
$msg->send;
