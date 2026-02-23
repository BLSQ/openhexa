FROM mcr.microsoft.com/playwright:v1.58.2-jammy


# Set the working directory
WORKDIR /code

# Copy your project files into the Docker container
COPY package.json package-lock.json /code/
RUN npm install -y && npx playwright install

COPY entrypoint.sh playwright.config.js /code/

COPY tests /code/tests

# Run Playwright tests
ENTRYPOINT ["/code/entrypoint.sh"]