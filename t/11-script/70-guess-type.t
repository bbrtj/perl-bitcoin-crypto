use v5.10;
use strict;
use warnings;
use Test::More;

use Bitcoin::Crypto qw(btc_script);

my @cases = (
	[
		'P2PK',
		[
			hex =>
				'410411db93e1dcdb8a016b49840f8c53bc1eb68a382e97b1482ecad7b148a6909a5cb2e0eaddfb84ccf9744464f82e160bfa9b8b64f9d4c03f999b8643f656b412a3ac'
		]
	],

	[
		'P2PK',
		[hex => '2102394fde5115357067c1d728210fc43aa1573ed52522b6f6d560fe29f1d0d1967cac']
	],

	[
		'P2PKH',
		[hex => '76a9142099fe62b65c69928ffef486987f8216fd68f9c488ac']
	],

	[
		'P2SH',
		[hex => 'a9149a8f9842b219cf5a54dfd389593b6a3dfe838a2687']
	],

	[
		'P2MS',
		[
			hex =>
				'532102002a57268073cbc5472d35d8f8fae2c52825241592f53e53ae516913d8c82bd121026c1061b95ccfc52594c9b376382e2f0240a523b3b1dc5db6a9cdd9730a4a0c2121029e8c3ae6c0516df4075089ab9475c9335985569ac0f3b9f1a4b0d946785937cd2102bf0faf4d948a56a6d78d1b87c6a62c9172005409da2f44f9ff6267dfde3cfd482103ba7c7d7b8d2379de450441445c30a638c555305cbe044abb88f10643d9621bf055ae'
		]
	],

	[
		'P2WPKH',
		[hex => '00145f011e3cfa337698e7fe4502143eb6ada0b5a3d1']
	],

	[
		'P2WSH',
		[hex => '0020e5c7c00d174631d2d1e365d6347b016fb87b6a0c08902d8e443989cb771fa7ec']
	],

	[
		'NULLDATA',
		[hex => '6a0b68656c6c6f20776f726c64']
	],

	[
		'NULLDATA',
		[
			hex =>
				'6a4c504d454d4f5f35363738395f3132333435363738395f3132333435363738395f3132333435363738395f3132333435363738395f3132333435363738395f3132333435363738395f313233343536373839'
		]
	],

	# P2PKH, but OP_CHECKSIG is duplicated
	[
		undef,
		[hex => '76a9142099fe62b65c69928ffef486987f8216fd68f9c488acac']
	],
);

my $case_num = 0;
foreach my $case (@cases) {
	my ($type, $raw_script) = @$case;
	my $type_str = $type // 'no type';

	subtest "testing script type guessing for case $case_num ($type_str)" => sub {
		my $script = btc_script->from_serialized($raw_script);

		my $got_type = $script->type // 'no type';
		is !!$script->has_type, !!$type, 'has_type ok';
		is $got_type, $type_str, 'type ok';
	};

	++$case_num;
}

done_testing;
