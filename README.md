Deploy: aptos move publish
Create pool: aptos move run --function-id <contract-addr>::staking::init_pool
Fund pool: aptos move run --function-id <contract-addr>::staking::fund_pool --args u64:100000000
User stake: aptos move run --function-id <contract-addr>::staking::stake --args u64:10000000
User claim: aptos move run --function-id <contract-addr>::staking::claim --args address:<admin_address>
