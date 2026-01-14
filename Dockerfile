# Stage 1: Build the application
FROM node:16 AS build-step

WORKDIR /app

# Copy package files and install dependencies
COPY package.json package-lock.json ./
RUN npm install

# Copy the rest of the application source code
COPY . .

# Add node_modules/.bin to PATH so we can run browserify
ENV PATH="./node_modules/.bin:/Users/dpowell/.antigravity/antigravity/bin:/Users/dpowell/.nvm/versions/node/v20.19.6/bin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/X11/bin:/usr/local/share/dotnet:~/.dotnet/tools:/usr/local/go/bin:/opt/podman/bin:/Users/dpowell/.antigravity/antigravity/bin:/Users/dpowell/.nvm/versions/node/v20.19.6/bin:/Users/dpowell/.nvm/versions/node/v20.14.0/bin:/Users/dpowell/miniconda3/condabin:/Users/dpowell/bin:/opt/homebrew/bin/:/opt/homebrew/sbin/:/Users/dpowell/.juliaup/bin:/Applications/iTerm.app/Contents/Resources/utilities"

# Compile the CoffeeScript to JavaScript
# This command mimics 'make compile'
RUN browserify -t coffeeify -t browserify-css src/main.coffee -o build.js

# Stage 2: Serve the application with Nginx
FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Clean the default Nginx static files
RUN rm -rf ./*

# Copy the built JavaScript file
COPY --from=build-step /app/build.js .

# Copy HTML and other static assets
COPY --from=build-step /app/pan.html .
COPY --from=build-step /app/index.html .
COPY --from=build-step /app/pan.index .

# Copy test data files
COPY --from=build-step /app/test.proteinortho .
COPY --from=build-step /app/test.strains .
COPY --from=build-step /app/test.descriptions .

# Copy CSS (found in src/pan.css, though likely bundled, we include it as the Makefile did)
COPY --from=build-step /app/src/pan.css .

# Expose port 80
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
