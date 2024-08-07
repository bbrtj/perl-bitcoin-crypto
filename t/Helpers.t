use Test2::V0;
use Bitcoin::Crypto::Helpers qw(pad_hex ensure_length);

subtest 'testing pad_hex' => sub {
	my @hexes = qw(1a3efb 1a3ef 0);

	for my $hex (@hexes) {
		my $from_bi = substr Math::BigInt->from_hex("0x$hex")->as_hex(), -length $hex;
		my $from_pack = substr unpack('H*', pack('H*', pad_hex($hex))), -length $hex;
		is($from_pack, $from_bi, 'hex packing ok');
	}
};

subtest 'testing ensure_length' => sub {
	is(
		ensure_length(pack('x4'), 4),
		pack('x4'), 'ensuring length does not change data for equal length'
	);
	is(ensure_length(pack('x30'), 32), pack('x32'), 'ensuring length adds missing zero bytes');

	ok dies {
		ensure_length pack('x5'), 4;
	}, 'packed data that was too long failed as expected';
};

done_testing;

