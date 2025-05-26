# doge.sh

`doge.sh` is a shell script for interacting with the [DOGE API](https://api.doge.gov/docs) from the command line.

## Usage

You can use this script to scrape any of the following endpoints: `contracts`, `grants`, `leases` and `payments`.

Just feed the script an endpoint and it should download all of the results to a single JSON file.

For example, to download all of the contracts listed at doge.gov, you can call this:

```sh
./doge.sh contracts
```

## Dependencies

- `curl`
- `jq` 

## Getting Started

1. Clone this repository.
2. Make the script executable:

    ```sh
    chmod +x doge.sh
    ```

3. Run the script.
4. That's all!