use Test2::V0;
use Bitcoin::Crypto::Network;

subtest 'registering invalid network fails' => sub {
	my $starting_count = scalar Bitcoin::Crypto::Network->find;

	my $litecoin = {
		id => 'litecoin',
		name => 'Litecoin Mainnet',
		p2pkh_byte => "\x30",
	};

	ok dies {
		Bitcoin::Crypto::Network->register(%$litecoin);
	}, 'invalid network validation fails';

	cmp_ok(
		Bitcoin::Crypto::Network->find, '==', $starting_count,
		'network list unchanged'
	);
};

subtest 'registering valid network succeeds' => sub {
	my $litecoin = {
		id => 'litecoin',
		name => 'Litecoin Mainnet',
		p2pkh_byte => "\x30",
		wif_byte => "\xb0",
	};

	ok lives {
		$litecoin = Bitcoin::Crypto::Network->register(%$litecoin);
		isa_ok $litecoin, 'Bitcoin::Crypto::Network';
		is(Bitcoin::Crypto::Network->get($litecoin->id)->id, $litecoin->id);
	}, 'network validates and gets registered';
};

subtest 'setting default network works' => sub {
	my $litecoin = Bitcoin::Crypto::Network->get('litecoin');
	$litecoin->set_default;

	is(
		Bitcoin::Crypto::Network->get->id, $litecoin->id,
		'network successfully flagged as default'
	);
};

subtest 'finding a network works' => sub {
	my $litecoin = Bitcoin::Crypto::Network->get('litecoin');

	is [Bitcoin::Crypto::Network->find(sub { shift->wif_byte eq "\xb0" })], [$litecoin->id],
		'network found successfully';
	is [Bitcoin::Crypto::Network->find(sub { shift->name eq 'unexistent' })], [],
		'non-existent network not found';
};

subtest 'single-network mode works' => sub {
	Bitcoin::Crypto::Network->get('bitcoin_testnet')->set_single;

	is(Bitcoin::Crypto::Network->get->id, 'bitcoin_testnet', 'default network ok');
	is(!!Bitcoin::Crypto::Network->single_network, !!1, 'single network ok');

	Bitcoin::Crypto::Network->get('bitcoin')->set_default;
	is(Bitcoin::Crypto::Network->get->id, 'bitcoin', 'default network 2 ok');
	is(!!Bitcoin::Crypto::Network->single_network, !!0, 'single network 2 ok');
};

subtest 'unregistering a network works' => sub {
	Bitcoin::Crypto::Network->get('litecoin')->unregister;

	ok !Bitcoin::Crypto::Network->find(sub { shift->id eq 'litecoin' }),
		'unregistered network not found';
};

done_testing;

