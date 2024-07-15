[![codecov](https://codecov.io/github/onchainification/robosaver/graph/badge.svg?token=745LCSOH0I)](https://codecov.io/github/onchainification/robosaver)

# RoboSaver

RoboSaver turns your [Gnosis Pay card](https://gnosispay.com/) into an automated savings account!

Unused [EURe](https://monerium.com/tokens/) on your card gets deposited into a liquidity pool, where it collects yield and swapping fees. But as soon as your card's balance gets below a certain threshold, the RoboSaver will withdraw some EURe from the pool for you and top up your card. Thus creating the perfect balance between having EURe ready for spending and putting EURe to work!

<p align="center"><img src="diagram.drawio.png"></p>

## 1. Technical Details

Only a single smart contract is needed; `RoboSaverVirtualModule`. The module is "virtual", since it doesn't get installed on the Gnosis Pay Safe directly, but on the `Delay` module instead. This way all of its transactions still respect the necessary delay needed to eventually settle with Visa.

Currently the contract is automated by having a keeper call `checkUpkeep` to see if any action is needed, and, if needed, then via `performUpkeep` internally call `_adjustPool` to perform that necessary action.

### 1.1 External Methods

- `checkUpkeep()`: a view function that determines whether the balance of the card is in surplus or deficit; returns whether an adjustment to the pool is needed and the payload needed to do so
- `performUpkeep(bytes calldata _performData))`: call the necessary internal method needed to rebalance the pool

## 2. Installation

### 2.1 Build

After cloning the repo, run `forge build` to initiate a compilation and fetch necessary dependencies.

Compilation of the contract at the end will raise some errors; this is because currently the `delay-module` requires a separate installation of dependencies. To fix this, run `yarn install --cwd lib/delay-module` (or `yarn install` with your current working directory being `lib/delay-module`).

Finally, copy `.env.example` to `.env` and populate it.

### 2.2 Test

```
$ forge test -vvvv
```

### 2.3 Local Deployment

```
$ make startAnvil
```

```
$ make deployAnvil
```

## 3. `checkUpkeep(bytes)` raw values returned mapping (`bytes` -> `string`)

| Bytes    | Readable String |
| -------- | ------- |
| 0x5669727475616c206d6f64756c65206973206e6f7420656e61626c6564000000  | Virtual module is not enabled    |
| 0x45787465726e616c207472616e73616374696f6e20696e2071756575652c207761697420666f7220697420746f20626520657865637574656400000000000000 | External transaction in queue, wait for it to be executed     |
| 0x496e7465726e616c207472616e73616374696f6e20696e20636f6f6c646f776e2073746174757300000000000000000000000000000000000000000000000000    | Internal transaction in cooldown status    |
| 0x4e6f207374616b6564204250542062616c616e6365206f6e20746865206361726400000000000000000000000000000000000000000000000000000000000000 | No staked BPT balance on the card |
| 0x4e6569746865722064656669636974206e6f7220737572706c75733b206e6f20616374696f6e206e656564656400000000000000000000000000000000000000  | Neither deficit nor surplus; no action needed |