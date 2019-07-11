## TODO

- Set DAI, Compound cDAI addresses

- Approve 0x-1 contracts balance to cDAI

- NOT - Accept DAI only. (reject all other payments or allow to withdraw by owner)

- Send DAI to compound to mint cDAI (https://compound.finance/developers#mint)

- Add cDAI to user's balance

-----

- Use a specific cDAI amount to get DAI (https://compound.finance/developers#redeem)

- Get a specific DAI amount for cDAI (https://compound.finance/developers#redeem-underlying)

- Get user details. (cDAI, DAI, balanceOf, balanceOfUnderlying)

- Set and track cDAI balance of users.





Kovan contracts:
DAI 0xc4375b7de8af5a38a93548eb8453a498222c4ff2
cDAI 0xb6b09fbffba6a5c4631e5f7b2e3ee183ac259c0d
cETH 0xd96dbd1d1a0bfdae6ada7f5c1cb6eaa485c9ab78
Comptroller 0x3ca5a0e85ad80305c2d2c4982b2f2756f1e747a5
PriceOracle 0x4b6419f70fbee1661946f165563c1de0d35e618c



### Code samples

- Mint
```sol
Erc20 underlying = Erc20(0xToken...);     // get a handle for the underlying asset contract
CErc20 cToken = CErc20(0x3FDA...);        // get a handle for the corresponding cToken contract
underlying.approve(address(cToken), 100); // approve the transfer
assert(cToken.mint(100) == 0);            // mint the cTokens and assert there is no error
```

- Redeem
```
CEther cToken = CEther(0x3FDB...);
require(cToken.redeem(7) == 0, "something went wrong");
```
