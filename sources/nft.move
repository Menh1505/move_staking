module smurf::staking {
    use std::signer;
    use std::vector;
    use std::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::object;
    use aptos_framework::account::create_signer_with_capability;
    use aptos_framework::account;
    use aptos_token_objects::token;

    /// Error codes
    const EALREADY_INITIALIZED: u64 = 1;
    const EUNAUTHORIZED: u64 = 2;
    const EEARLY_WITHDRAW: u64 = 3;
    const ENOT_STAKING: u64 = 4;

    const CLAIM_REWARD: u64 = 3000000; //0.03APT
    const SECONDS_IN_YEAR: u64 = 10;
    const STAKING_DURATION: u64 = 2592000; // 30 days
    

    /// ======= Initialization ========
    struct StakeCoinInfo has key {
        amount: vector<u64>,
        start_time: vector<u64>,
    }

    struct StakeNftInfo has key {
        token: vector<object::Object<token::Token>>,
        start_time: vector<u64>,
    }

    struct ResourceAccount has key {
        resource_addr: address,
        signer_cap: account::SignerCapability,
    }

    public entry fun fund_pool(admin: &signer, amount: u64) acquires ResourceAccount {
        let coins = coin::withdraw<AptosCoin>(admin, amount);
        let resource_account = borrow_global_mut<ResourceAccount>(signer::address_of(admin));

        coin::deposit<AptosCoin>(resource_account.resource_addr, coins);
    }

    public entry fun init_staking_pool(admin: &signer, seed: vector<u8>) {
        // Ensure the `StakingPool` resource does not already exist
        assert!(
            !exists<ResourceAccount>(signer::address_of(admin)),
            EALREADY_INITIALIZED
        );

        // Create the resource account
        let (resource, signer_cap) = account::create_resource_account(admin, copy seed);
        let resource_account_signer = create_signer_with_capability(
            &signer_cap,
        );
        let resource_addr = signer::address_of(&resource);

        coin::register<AptosCoin>(&resource_account_signer);
        // Store the `StakingPool` resource in the admin's account
        move_to(admin, ResourceAccount {
            resource_addr: resource_addr,
            signer_cap,
        });
    }

    #[view]
    public fun get_pool_balance(admin: address): u64 acquires ResourceAccount {
        let resource_account = borrow_global<ResourceAccount>(admin);

        coin::balance<AptosCoin>(resource_account.resource_addr)
    }

    // ======= NFT staking ========
    #[view]
    public fun get_staking_nft_info(staker_addr: address): (vector<object::Object<token::Token>>, vector<u64>) acquires StakeNftInfo {
        assert!(exists<StakeNftInfo>(staker_addr), ENOT_STAKING); // Ensure the user has staked an NFT

        let  stake_nft_info = borrow_global<StakeNftInfo>(staker_addr);
        (stake_nft_info.token, stake_nft_info.start_time)
    }

    public entry fun stake_nft(
        staker: &signer,
        admin_addr: address,                
        token_id: object::Object<token::Token>,                                                                              
    ) acquires ResourceAccount, StakeNftInfo{
        let pool = borrow_global<ResourceAccount>(admin_addr);
        let pool_address = pool.resource_addr;

        let now = timestamp::now_seconds();
        let staker_address = signer::address_of(staker);

        object::transfer<token::Token>(
            staker,
            token_id,
            pool_address,
        );

        let staker_nft_info ;
        if (exists<StakeNftInfo>(staker_address)) {
            staker_nft_info = borrow_global_mut<StakeNftInfo>(signer::address_of(staker))
        } else {
            move_to<StakeNftInfo>(staker, StakeNftInfo {
                token: vector::empty(),
                start_time: vector::empty(),
            });
            staker_nft_info = borrow_global_mut<StakeNftInfo>(signer::address_of(staker))
        };

        staker_nft_info.token.push_back(token_id);
        staker_nft_info.start_time.push_back(now);
    }

    public entry fun claim_nft(
        staker: &signer,
        admin_addr: address,                                                                                             
    ) acquires ResourceAccount, StakeNftInfo{
        assert!(exists<StakeNftInfo>(signer::address_of(staker)), ENOT_STAKING); // Ensure the user has staked an NFT
        let StakeNftInfo {token, start_time} = borrow_global_mut<StakeNftInfo>(signer::address_of(staker));

        let now = timestamp::now_seconds();
        let resource_account = borrow_global<ResourceAccount>(admin_addr);
        let resource_account_signer = create_signer_with_capability(
            &resource_account.signer_cap,
        );

        while(true){
            let current_start_time = start_time[0];
            let stake_duration = now - current_start_time;
            if (stake_duration < STAKING_DURATION) {
                break;
            };

            object::transfer<token::Token>(
                &resource_account_signer,
                token[0],
                signer::address_of(staker),
            );
            
            let payout = coin::withdraw(&resource_account_signer, CLAIM_REWARD);
            coin::deposit<AptosCoin>(signer::address_of(staker), payout);

            vector::remove(start_time, 0);
            vector::remove(token, 0);
        };
    }

    // ======= Coin staking ========
    #[view]
    public fun get_staking_coin_info(staker_addr: address): (vector<u64>, vector<u64>) acquires StakeCoinInfo {
        assert!(exists<StakeCoinInfo>(staker_addr), ENOT_STAKING); // Ensure the user has staked an NFT
        let stake_coin_info = borrow_global<StakeCoinInfo>(staker_addr);

        (stake_coin_info.amount, stake_coin_info.start_time)
    }

    public entry fun stake_coin(staker: &signer, amount: u64, admin_addr: address) acquires ResourceAccount, StakeCoinInfo {
        let staker_address = signer::address_of(staker);
        let resource_account = borrow_global<ResourceAccount>(admin_addr);

        let staker_info;
        if (exists<StakeCoinInfo>(staker_address)) {
            staker_info = borrow_global_mut<StakeCoinInfo>(signer::address_of(staker))
        } else {
            move_to<StakeCoinInfo>(staker, StakeCoinInfo {
                amount: vector::empty(),
                start_time: vector::empty(),
            });
            staker_info = borrow_global_mut<StakeCoinInfo>(signer::address_of(staker))
        };

        let coins = coin::withdraw<AptosCoin>(staker, amount);
        coin::deposit<AptosCoin>(resource_account.resource_addr, coins); // temporarily hold

        let now = timestamp::now_seconds();
        staker_info.amount.push_back(amount);
        staker_info.start_time.push_back(now);
    }

    public entry fun claim_coin(staker: &signer, admin: address) acquires StakeCoinInfo, ResourceAccount {
        let staker_addr = signer::address_of(staker);

        assert!(exists<StakeCoinInfo>(staker_addr), ENOT_STAKING);
        let StakeCoinInfo { amount, start_time } = borrow_global_mut<StakeCoinInfo>(staker_addr);
        let resource_account = borrow_global<ResourceAccount>(admin);
        let resource_account_signer = create_signer_with_capability(
            &resource_account.signer_cap,
        );

        let now = timestamp::now_seconds();

        while(true){
            let current_start_time = start_time[0];
            let stake_duration = now - current_start_time;
            if (stake_duration < STAKING_DURATION) {
                break;
            };

            let current_amount = amount[0];
            let total = current_amount + CLAIM_REWARD;
            let payout = coin::withdraw(&resource_account_signer, total);
            coin::deposit<AptosCoin>(staker_addr, payout);

            vector::remove(start_time, 0);
            vector::remove(amount, 0);
        }
    }
}
