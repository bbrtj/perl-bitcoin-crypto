use v5.10;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use ScriptTest;

use Bitcoin::Crypto::Script;

subtest 'testing addition and subtraction on single byte' => sub {
	my @ops = (
		'OP_15',
		'OP_16',
		'OP_ADD',
		'OP_7',
		'OP_SUB',
	);

	my $script = Bitcoin::Crypto::Script->new;
	script_fill($script, @ops);

	ops_are($script, \@ops);
	stack_is($script, ["\x18"]);
};

subtest 'testing addition and subtraction on two bytes' => sub {
	my @ops = (
		'ff01',
		'OP_14',
		'OP_SUB',
		'OP_16',
		'OP_ADD',
	);

	my $script = Bitcoin::Crypto::Script->new;
	script_fill($script, @ops);

	ops_are($script, \@ops);
	stack_is($script, ["\x01\x02"]);
};

done_testing;
