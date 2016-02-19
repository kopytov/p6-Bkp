use Bkp;
use Bkp::Src;

unit class Bkp::Src::Ploop is Bkp::Src;

has Str $.suffix = 'tar';
has @.cmd = <tar --warning=none --numeric-owner -cf ->;

has CTID    $.ctid is required;
has Str     $.vzctl = 'vzctl';
has DirPath $.vztmp = '/vz/vztmp';
has         $.exclude;
has Str     $!uuid;
has Str     $!mntpoint;

my regex hex { <[ 0 .. 9 a .. f A .. F ]> }
my regex uuid {
    <hex> ** 8 '-'
    <hex> ** 4 '-'
    <hex> ** 4 '-'
    <hex> ** 4 '-'
    <hex> ** 12
}

method uuid () {
    return $!uuid if $!uuid.defined;
    my $proc;

    $proc = run «$!vzctl snapshot-list $!ctid -H -ouuid,name», :out;
    $proc.out.slurp-rest ~~ / '{' ( <uuid> ) '}' \s+ bkp /;
    if $0.defined {
        $!uuid = ~$0;
        return $!uuid;
    }

    $proc = run «$!vzctl snapshot $!ctid --name bkp --skip-config
        --skip-suspend», :out;
    $proc.out.slurp-rest
        ~~ / 'Snapshot {' ( <uuid> ) '} has been successfully created' /;
    fail "Failed to create snapshot for CT$!ctid" unless $0.defined;
    $!uuid = ~$0;
    return $!uuid;
}

method mount () {
    try {
        run «mountpoint -q $!mntpoint»;
        CATCH {
            when X::Proc::Unsuccessful {
                .throw if .proc.exitcode != 1;
                run «$!vzctl --quiet snapshot-mount $!ctid --id $.uuid
                  --target $!mntpoint»;
            }
        }
    }
}

method umount () {
    return unless $!mntpoint.defined;
    try {
        run «mountpoint -q $!mntpoint»;
        CATCH {
            when X::Proc::Unsuccessful {
                .throw if .proc.exitcode != 1;
                return;
            }
        }
    }
    run «$!vzctl --quiet snapshot-umount $!ctid --id $.uuid»;
}

method mntpoint () {
    return $!mntpoint if $!mntpoint.defined;
    $!mntpoint = "$!vztmp/mnt$!ctid";
    $!mntpoint.IO.mkdir unless $!mntpoint.IO.d;
    $.mount;
    return $!mntpoint;
}

method clean-up () {
    if $!mntpoint.defined {
        $.umount;
        $!mntpoint.IO.rmdir;
        $!mntpoint = Nil;
    }

    if $!uuid.defined {
        run «$!vzctl --quiet snapshot-delete $!ctid --id $!uuid»;
        $!uuid = Nil;
    }
}

method build-cmd () {
    my @cmd = @!cmd.clone;
    @cmd.append: «-C $.mntpoint»;
    @cmd.append: $!exclude.list
      .grep(*.defined)
      .map( { .starts-with('/') ?? .substr(1) !! $_ } )
      .map( '--exclude=' ~ * );
    @cmd.append: $.mntpoint.IO.dir».basename;
    return @cmd;
}
