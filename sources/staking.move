module staking::staking {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::aptos_coin::{AptosCoin};

    const INTEREST_RATE: u64 = 10; // 10%/year, split by seconds
    const SECONDS_IN_YEAR: u64 = 31536000;

    struct StakeInfo has key {
        amount: u64,
        start_time: u64,
    }

    struct Pool has key {
        vault: coin::Coin<AptosCoin>,
    }

    public entry fun init_pool(admin: &signer) {
        let vault = coin::zero<AptosCoin>();
        move_to(admin, Pool { vault });
    }

    public entry fun fund_pool(admin: &signer, amount: u64) acquires Pool {
        let coins = coin::withdraw<AptosCoin>(admin, amount);
        let pool = borrow_global_mut<Pool>(signer::address_of(admin));
        coin::merge(&mut pool.vault, coins);
    }

    public entry fun stake(user: &signer, amount: u64) {
        assert!(!exists<StakeInfo>(signer::address_of(user)), 1);
        let now = timestamp::now_seconds();
        let coins = coin::withdraw<AptosCoin>(user, amount);
        coin::deposit<AptosCoin>(signer::address_of(user), coins); // temporarily hold
        move_to(user, StakeInfo { amount, start_time: now });
    }

    public entry fun claim(user: &signer, admin: address) acquires StakeInfo, Pool {
        let user_addr = signer::address_of(user);
        let StakeInfo { amount, start_time } = move_from<StakeInfo>(user_addr);
        let now = timestamp::now_seconds();
        let duration = now - start_time;
        let interest = amount * INTEREST_RATE * duration / (SECONDS_IN_YEAR * 100);

        let total = amount + interest;
        let pool = borrow_global_mut<Pool>(admin);
        let payout = coin::extract(&mut pool.vault, total);
        coin::deposit<AptosCoin>(user_addr, payout);
    }

    public fun get_pending_reward(user: address): u64 acquires StakeInfo {
        if (!exists<StakeInfo>(user)) {
            return 0;
        };
        let stake_info = borrow_global<StakeInfo>(user);
        let now = timestamp::now_seconds();
        let duration = now - stake_info.start_time;
        let interest = stake_info.amount * INTEREST_RATE * duration / (SECONDS_IN_YEAR * 100);
        interest
    }
} 