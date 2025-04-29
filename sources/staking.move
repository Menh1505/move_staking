module smurf::smurf3 {
    use std::signer;
    use std::vector;
    use std::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin};
    use aptos_framework::object;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_token_objects::token;

    const EALREADY_INITIALIZED: u64 = 1;
    const EUNAUTHORIZED: u64 = 2;
    const EEARLY_WITHDRAW: u64 = 3;
    const ENOT_STAKING: u64 = 4;
    const EINSUFFICIENT_BALANCE: u64 = 5;
    const EINVALID_TOKEN: u64 = 6;
    const EPAUSED: u64 = 7;
    const ENOT_INIT_POOL: u64 = 8;

    const CLAIM_REWARD: u64 = 3_000_000;
    const STAKING_DURATION: u64 = 60; // 30 days
    const ADMIN_ADDRESS: address = @0x6d16e46688111c9ffc4d7c72e7a25f40c50133b725642a2faf1cc54b739fd6bb; 

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
        signer_cap: SignerCapability,
        admin: address,
        paused: bool,
        stake_nft_events: EventHandle<StakeNftEvent>,
        claim_nft_events: EventHandle<ClaimNftEvent>,
        stake_coin_events: EventHandle<StakeCoinEvent>,
        claim_coin_events: EventHandle<ClaimCoinEvent>,
        fund_pool_events: EventHandle<FundPoolEvent>,
    }

    struct StakeNftEvent has drop, store {
        staker: address,
        token_id: address,
        start_time: u64,
    }

    struct ClaimNftEvent has drop, store {
        staker: address,
        token_id: address,
        reward: u64,
    }

    struct StakeCoinEvent has drop, store {
        staker: address,
        amount: u64,
        start_time: u64,
    }

    struct ClaimCoinEvent has drop, store {
        staker: address,
        amount: u64,
        reward: u64,
    }

    struct FundPoolEvent has drop, store {
        admin: address,
        amount: u64,
    }

    public entry fun init_staking_pool(admin: &signer, seed: vector<u8>) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, EUNAUTHORIZED);
        assert!(!exists<ResourceAccount>(admin_addr), EALREADY_INITIALIZED);

        let (resource, signer_cap) = account::create_resource_account(admin, seed);
        let resource_signer = account::create_signer_with_capability(&signer_cap);
        let resource_addr = signer::address_of(&resource);

        coin::register<AptosCoin>(&resource_signer);
        move_to(admin, ResourceAccount {
            resource_addr,
            signer_cap,
            admin: admin_addr,
            paused: false,
            stake_nft_events: account::new_event_handle<StakeNftEvent>(&resource_signer),
            claim_nft_events: account::new_event_handle<ClaimNftEvent>(&resource_signer),
            stake_coin_events: account::new_event_handle<StakeCoinEvent>(&resource_signer),
            claim_coin_events: account::new_event_handle<ClaimCoinEvent>(&resource_signer),
            fund_pool_events: account::new_event_handle<FundPoolEvent>(&resource_signer),
        });
    }

    public entry fun fund_pool(admin: &signer, amount: u64) acquires ResourceAccount {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, EUNAUTHORIZED);
        let pool = borrow_global_mut<ResourceAccount>(admin_addr);
        assert!(!pool.paused, EPAUSED);

        let coins = coin::withdraw<AptosCoin>(admin, amount);
        coin::deposit<AptosCoin>(pool.resource_addr, coins);

        event::emit_event(&mut pool.fund_pool_events, FundPoolEvent {
            admin: admin_addr,
            amount,
        });
    }

    public entry fun toggle_pause(admin: &signer) acquires ResourceAccount {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == ADMIN_ADDRESS, EUNAUTHORIZED);
        let pool = borrow_global_mut<ResourceAccount>(admin_addr);
        pool.paused = !pool.paused;
    }

    #[view]
    public fun get_pool_balance(): u64 acquires ResourceAccount {
        if(exists<ResourceAccount>(ADMIN_ADDRESS)) {
            let pool = borrow_global<ResourceAccount>(ADMIN_ADDRESS);
            coin::balance<AptosCoin>(pool.resource_addr)
        } else {
            0
        }
    }
    #[view]
    public fun test_exists(): u8 {
        if(exists<ResourceAccount>(ADMIN_ADDRESS)){
            1
        } else {
            assert!(false, ENOT_INIT_POOL);
            0
        }
    }

    #[view]
    public fun get_staking_nft_info(staker_addr: address): (vector<object::Object<token::Token>>, vector<u64>) acquires StakeNftInfo {
        if(exists<StakeNftInfo>(staker_addr) ){
            let stake_nft_info = borrow_global<StakeNftInfo>(staker_addr);
            (stake_nft_info.token, stake_nft_info.start_time)
        }else {
            (vector::empty<object::Object<token::Token>>(), vector::empty<u64>())
        }
    }

    public entry fun stake_nft(
        staker: &signer,
        token_id: object::Object<token::Token>,
    ) acquires ResourceAccount, StakeNftInfo {
        let pool = borrow_global_mut<ResourceAccount>(ADMIN_ADDRESS);
        assert!(!pool.paused, EPAUSED);
        assert!(object::is_owner<token::Token>(token_id, signer::address_of(staker)), EINVALID_TOKEN);

        let now = timestamp::now_seconds();
        let staker_addr = signer::address_of(staker);

        object::transfer<token::Token>(staker, token_id, pool.resource_addr);

        let staker_nft_info = if (exists<StakeNftInfo>(staker_addr)) {
            borrow_global_mut<StakeNftInfo>(staker_addr)
        } else {
            move_to(staker, StakeNftInfo {
                token: vector::empty(),
                start_time: vector::empty(),
            });
            borrow_global_mut<StakeNftInfo>(staker_addr)
        };

        vector::push_back(&mut staker_nft_info.token, token_id);
        vector::push_back(&mut staker_nft_info.start_time, now);

        event::emit_event(&mut pool.stake_nft_events, StakeNftEvent {
            staker: staker_addr,
            token_id: object::object_address(&token_id),
            start_time: now,
        });
    }

    public entry fun claim_nft(
        staker: &signer,
    ) acquires ResourceAccount, StakeNftInfo {
        let pool = borrow_global_mut<ResourceAccount>(ADMIN_ADDRESS);
        assert!(!pool.paused, EPAUSED);
        let staker_addr = signer::address_of(staker);

        if (!exists<StakeNftInfo>(staker_addr)) {
            assert!(false, ENOT_STAKING);
        };

        let stake_nft_info = borrow_global_mut<StakeNftInfo>(staker_addr);
        let resource_signer = account::create_signer_with_capability(&pool.signer_cap);
        let now = timestamp::now_seconds();
        let pool_balance = coin::balance<AptosCoin>(pool.resource_addr);

        assert!(now - *vector::borrow(&stake_nft_info.start_time, 0) > STAKING_DURATION, EEARLY_WITHDRAW);

        let i = 0;
        while (i < vector::length(&stake_nft_info.start_time)) {
            let start_time = *vector::borrow(&stake_nft_info.start_time, i);
            let stake_duration = now - start_time;

            if (stake_duration < STAKING_DURATION) {
                break
            };

            assert!(pool_balance >= CLAIM_REWARD, EINSUFFICIENT_BALANCE);
            let token_id = vector::remove(&mut stake_nft_info.token, i);
            vector::remove(&mut stake_nft_info.start_time, i);

            object::transfer<token::Token>(&resource_signer, token_id, staker_addr);
            let payout = coin::withdraw<AptosCoin>(&resource_signer, CLAIM_REWARD);
            coin::deposit<AptosCoin>(staker_addr, payout);
            pool_balance = pool_balance - CLAIM_REWARD;

            event::emit_event(&mut pool.claim_nft_events, ClaimNftEvent {
                staker: staker_addr,
                token_id: object::object_address(&token_id),
                reward: CLAIM_REWARD,
            });
        };

        if (vector::is_empty(&stake_nft_info.token)) {
            move_to(staker, StakeNftInfo {
                token: vector::empty(),
                start_time: vector::empty(),
            });
        };
    }

    #[view]
    public fun get_staking_coin_info(staker_addr: address): (vector<u64>, vector<u64>) acquires StakeCoinInfo {
        if (exists<StakeCoinInfo>(staker_addr)){
            let stake_coin_info = borrow_global<StakeCoinInfo>(staker_addr);
            (stake_coin_info.amount, stake_coin_info.start_time)
        } else {
            (vector::empty<u64>(), vector::empty<u64>())
        }
    }

    public entry fun stake_coin(
        staker: &signer,
        amount: u64,
    ) acquires ResourceAccount, StakeCoinInfo {
        let pool = borrow_global_mut<ResourceAccount>(ADMIN_ADDRESS);
        assert!(!pool.paused, EPAUSED);
        let staker_addr = signer::address_of(staker);

        let staker_info = if (exists<StakeCoinInfo>(staker_addr)) {
            borrow_global_mut<StakeCoinInfo>(staker_addr)
        } else {
            move_to(staker, StakeCoinInfo {
                amount: vector::empty(),
                start_time: vector::empty(),
            });
            borrow_global_mut<StakeCoinInfo>(staker_addr)
        };

        let coins = coin::withdraw<AptosCoin>(staker, amount);
        coin::deposit<AptosCoin>(pool.resource_addr, coins);

        let now = timestamp::now_seconds();
        vector::push_back(&mut staker_info.amount, amount);
        vector::push_back(&mut staker_info.start_time, now);

        event::emit_event(&mut pool.stake_coin_events, StakeCoinEvent {
            staker: staker_addr,
            amount,
            start_time: now,
        });
    }

    public entry fun claim_coin(
        staker: &signer,
    ) acquires ResourceAccount, StakeCoinInfo {
        let pool = borrow_global_mut<ResourceAccount>(ADMIN_ADDRESS);
        assert!(!pool.paused, EPAUSED);
        let staker_addr = signer::address_of(staker);
        assert!(exists<StakeCoinInfo>(staker_addr), ENOT_STAKING);

        let stake_coin_info = borrow_global_mut<StakeCoinInfo>(staker_addr);
        let resource_signer = account::create_signer_with_capability(&pool.signer_cap);
        let now = timestamp::now_seconds();
        let pool_balance = coin::balance<AptosCoin>(pool.resource_addr);

        if(!exists<StakeCoinInfo>(staker_addr)) {
            assert!(false, ENOT_STAKING);
        };

        assert!(now - *vector::borrow(&stake_coin_info.start_time, 0) > STAKING_DURATION, EEARLY_WITHDRAW);

        let i = 0;
        while (i < vector::length(&stake_coin_info.start_time)) {
            let start_time = *vector::borrow(&stake_coin_info.start_time, i);
            let stake_duration = now - start_time;

            if (stake_duration < STAKING_DURATION) {
                break
            };

            let amount = vector::remove(&mut stake_coin_info.amount, i);
            vector::remove(&mut stake_coin_info.start_time, i);
            let total = amount + CLAIM_REWARD;
            assert!(pool_balance >= total, EINSUFFICIENT_BALANCE);

            let payout = coin::withdraw<AptosCoin>(&resource_signer, total);
            coin::deposit<AptosCoin>(staker_addr, payout);
            pool_balance = pool_balance - total;

            event::emit_event(&mut pool.claim_coin_events, ClaimCoinEvent {
                staker: staker_addr,
                amount,
                reward: CLAIM_REWARD,
            });
        };
    }
}
