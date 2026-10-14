import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "images.unsplash.com" },
      { protocol: "https", hostname: "i.imgur.com" },
    ],
  },
  async rewrites() {
    return {
      afterFiles: [{ source: "/:path*", destination: "/:path*/index.html" }],
    };
  },
};

export default nextConfig;
