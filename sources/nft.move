module 0x0::nft {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::object;
    use aptos_framework::account::create_signer_with_capability;
    use aptos_framework::account;
    use aptos_token::token::{Self, TokenId, withdraw_token, deposit_token, Token};
    use aptos_framework::resource_account;

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

    public entry fun stake_nft(
        sender: &signer,                // Sender of the NFT
        collection_name: string::String,        // Name of the NFT collection
        token_name: string::String,             // Name of the NFT
        property_version: u64,          // Property version of the NFT
        amount: u64,                     // Amount of the NFT to transfer
        pool: address                  // Address of the staking pool
    ) {
        let token_id = aptos_token::token::create_token_id_raw(
            signer::address_of(sender),
            collection_name,
            token_name,
            property_version
        );

        aptos_token::token::transfer(sender, token_id, pool, amount);
    }

    public entry fun withdraw_nft(
        sender: &signer,
        admin_address: address,                
        token_id: address,                               
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
