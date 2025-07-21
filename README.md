## Cash Protocol

## Production Notes
- Deployer should deposit at least $1 into USDX and then into Consol, and then transfer ownership to the contract to lock it in. This will help defend against donation attacks.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
$ yarn solhint
$ lintspec src --compact
```

### Gas Snapshots

```shell
$ forge snapshot
```
