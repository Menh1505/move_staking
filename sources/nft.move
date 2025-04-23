module 0x0::nft {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::object;
    use aptos_framework::account::create_signer_with_capability;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use aptos_token_objects::token;

    /// Error codes
    const EALREADY_INITIALIZED: u64 = 1;
    const EUNAUTHORIZED: u64 = 2;

    struct StakingPool has key {
        resource_address: address,
        signer_cap: account::SignerCapability,
    }

    public entry fun init_staking_pool(admin: &signer, seed: vector<u8>) {
        // Ensure the `StakingPool` resource does not already exist
        assert!(
            !exists<StakingPool>(signer::address_of(admin)),
            EALREADY_INITIALIZED
        );

        // Create the resource account
        let (resource, signer_cap) = account::create_resource_account(admin, copy seed);
        let resource_addr = signer::address_of(&resource);

        // Store the `StakingPool` resource in the admin's account
        move_to(admin, StakingPool {
            resource_address: resource_addr,
            signer_cap,
        });
    }

    /// Get the resource address of the `StakingPool`.
    public fun get_resource_address(admin: address): address acquires StakingPool {
        let staking_pool = borrow_global<StakingPool>(admin);
        staking_pool.resource_address
    }

    public entry fun withdraw_nft(
        sender: &signer,
        admin_address: address,                
        token_id: object::Object<token::Token>,                               
        to: address,                                                
    ) acquires StakingPool{
       let pool = borrow_global<StakingPool>(admin_address);
       let pool_signer = create_signer_with_capability(
            &pool.signer_cap,
        );

        object::transfer<token::Token>(
            &pool_signer,
            token_id,
            to,
        );
    }
}
