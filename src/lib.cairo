use starknet::ContractAddress;

// Interfaces (these would typically be in separate files)
#[starknet::interface]
trait IERC20 <TContractState>{
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self : TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
trait IZkLend <TContractState>{
    fn supply(ref self: TContractState, token: ContractAddress, amount: u256);
    fn borrow(ref self: TContractState, token: ContractAddress, amount: u256);
}

#[starknet::interface]
trait INostra <TContractState>{
    fn deposit(ref self: TContractState, token: ContractAddress, amount: u256);
    fn borrow(ref self: TContractState, token: ContractAddress, amount: u256);
}

#[starknet::interface]
trait ISenseiStrategy <TContractState>{
    fn deposit(ref self: TContractState, amount: u256);
    fn compound_rewards(ref self: TContractState);
}

#[starknet::contract]
pub mod SenseiStrategy {
    use starknet::{ContractAddress, get_caller_address, get_contract_address,};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use core::array::ArrayTrait;
    use super::{IERC20Dispatcher, IERC20DispatcherTrait, IZkLendDispatcher, IZkLendDispatcherTrait, INostraDispatcher, INostraDispatcherTrait};
    // use core::option::OptionTrait;
    // use core::traits::Into;
    // use core::num::traits::Zero;


    #[storage]
    struct Storage {
        usdc: ContractAddress,
        eth: ContractAddress,
        strk: ContractAddress,
        zk_lend: ContractAddress,
        nostra: ContractAddress,
        user_balances: Map<ContractAddress, u256>,
    }

    // Constants
    const LOOP_COUNT: u8 = 4;
    const BORROW_FACTOR: u256 = 615; // 61.5% in basis points
    const NOSTRA_BORROW_FACTOR: u256 = 585; // 58.5% in basis points

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        usdc: ContractAddress,
        eth: ContractAddress,
        strk: ContractAddress,
        zk_lend: ContractAddress,
        nostra: ContractAddress
    ) {
        self.usdc.write(usdc);
        self.eth.write(eth);
        self.strk.write(strk);
        self.zk_lend.write(zk_lend);
        self.nostra.write(nostra);
    }

    // External functions
    #[abi(embed_v0)]
    impl SenseiStrategyImpl of super::ISenseiStrategy<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            let caller = get_caller_address();
            let this_contract = starknet::get_contract_address();
    
            // Transfer USDC from user to contract
            let erc20_contract = IERC20Dispatcher { contract_address: self.usdc.read() };
            erc20_contract.transfer_from(caller, this_contract, amount);

            let zkLend = IZkLendDispatcher { contract_address: self.zk_lend.read() };
            let nostra = INostraDispatcher { contract_address: self.nostra.read() };

    
            let mut current_amount = amount;
            let mut i: u8 = 0;
            loop {
                if i >= LOOP_COUNT {
                    break;
                }
    
                // Step 1: Supply USDC to zkLend
                erc20_contract.approve(self.zk_lend.read(), current_amount);
                zkLend.supply(self.usdc.read(), current_amount);
    
                // Step 2: Borrow ETH from zkLend
                let eth_to_borrow = (current_amount * BORROW_FACTOR) / 1000;
                zkLend.borrow(self.eth.read(), eth_to_borrow);
    
                // Step 3: Deposit ETH to Nostra
                erc20_contract.approve(self.nostra.read(), eth_to_borrow);
                nostra.deposit(self.eth.read(), eth_to_borrow);
    
                // Step 4: Borrow USDC from Nostra
                let usdc_to_borrow = (eth_to_borrow * NOSTRA_BORROW_FACTOR) / 1000;
                nostra.borrow(self.usdc.read(), usdc_to_borrow);
    
                // Prepare for next loop
                current_amount = usdc_to_borrow;
                i += 1;
            }
        }
    
        fn compound_rewards(ref self: ContractState) {
            let this_contract = get_contract_address();
            let erc20_contract = IERC20Dispatcher { contract_address: self.strk.read() };
            let strk_balance = erc20_contract.balance_of(this_contract);
    
            if strk_balance > 0 {
                // Sell STRK for USDC (simplified, in reality would use a DEX)
                let usdc_received = self.sell_strk_for_usdc(strk_balance);
    
                // Reinvest USDC
                self.deposit(usdc_received);
            }
        }
    }
  

    // Internal functions
    #[generate_trait]
    impl SenseiStrategyInternal of SenSeiStrategyInternalTrait {
        fn sell_strk_for_usdc(self: @ContractState, strk_amount: u256) -> u256 {
            // Implementation would interact with a DEX to swap STRK for USDC
            // For simplicity, I am just returning a mock value
            strk_amount * 2 // Assume 1 STRK = 2 USDC
        }
    }
}
