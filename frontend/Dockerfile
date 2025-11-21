FROM nginx:alpine

# Copy static HTML
COPY src/index.html /usr/share/nginx/html/index.html

# Fix permissions for nginx user
RUN chmod 644 /usr/share/nginx/html/index.html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
