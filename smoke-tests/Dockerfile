FROM mcr.microsoft.com/playwright:v1.45.0-jammy


# Set the working directory
WORKDIR /usr/src/app

# Copy your project files into the Docker container
COPY . .

# Install deps
RUN npm install


# Run Playwright tests
CMD ["npx", "playwright", "test"]