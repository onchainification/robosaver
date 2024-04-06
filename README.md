# RoboSaver

## Installation

### Build

after cloning the repo, run `forge build` to initiate a compilation and fetch necessary dependencies

currently the `delay-module` also requires a separate installation of dependencies:

```
yarn install --cwd lib/delay-module
```

finally, copy `.env.example` to `.env` and populate it

### Test

run `forge test -vvvv`
