# Smoke tests

## How to run smoke tests with docker

1. Build the docker image:
```bash
docker build -t smoke-tests .
```

2. Run the docker container:
```bash
docker run  -it -v "$(pwd):/usr/src/app" smoke-tests
```

## How to run smoke tests without docker
1. Install the dependencies:
```bash
npm install
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