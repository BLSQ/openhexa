# Smoke tests

## How to run smoke tests with docker

1. Build the docker image:
```bash
docker build -t smoke-tests .
```

2. Replace the necessary values in the command below and run the tests:
```bash
docker run  -it --net=host smoke-tests <URL> <username> <password>
```

If you want to mount the tests directory to the container, you can use the following command:
```bash
docker run  -it --net=host -v "$(pwd)/tests":/code/tests smoke-tests <URL> <username> <password>
```

## How to run smoke tests without docker

You have to have node.js installed on your machine. The minimum version required is 20.

1. Install the dependencies:
```bash
npm install
npx playwright install # Install Playwright configured browsers & deps
```

2. Configure the environment variables:
```bash
cp .env.dist .env
```

3. Run the tests with a visual interface:
```bash
npm run test:ui # With a visual interface
npm run test # Without a visual interface
```

## How to write smoke tests
1. Create a new test file in the `tests` directory.
2. Write your test using the [Playwright API](https://playwright.dev/docs).

You can also use the code generator to help you write tests using `npm run test:codegen`