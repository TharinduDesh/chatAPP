import React, { useEffect, useRef } from "react";
import { Box } from "@mui/material";

const AnimatedBackground = () => {
  const canvasRef = useRef(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const ctx = canvas.getContext("2d");

    // Resize canvas
    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener("resize", resize);

    // Circle object
    class Circle {
      constructor(x, y, radius, dx, dy, color) {
        this.x = x;
        this.y = y;
        this.radius = radius;
        this.dx = dx; // velocity X
        this.dy = dy; // velocity Y
        this.color = color;
      }
      draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2, false);
        ctx.fillStyle = this.color;
        ctx.fill();
        ctx.closePath();
      }
      update() {
        if (this.x + this.radius > canvas.width || this.x - this.radius < 0) {
          this.dx = -this.dx; // bounce horizontally
        }
        if (this.y + this.radius > canvas.height || this.y - this.radius < 0) {
          this.dy = -this.dy; // bounce vertically
        }
        this.x += this.dx;
        this.y += this.dy;
        this.draw();
      }
    }

    // Generate circles
    const circles = [];
    for (let i = 0; i < 20; i++) {
      const radius = Math.random() * 80 + 40;
      const x = Math.random() * (canvas.width - radius * 2) + radius;
      const y = Math.random() * (canvas.height - radius * 2) + radius;
      const dx = (Math.random() - 0.5) * 1; // Slower horizontal velocity
      const dy = (Math.random() - 0.5) * 1; // Slower vertical velocity
      const color = "rgba(255,255,255,0.1)";
      circles.push(new Circle(x, y, radius, dx, dy, color));
    }

    // Animation loop
    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      circles.forEach((circle) => circle.update());
      requestAnimationFrame(animate);
    };
    animate();

    return () => window.removeEventListener("resize", resize);
  }, []);

  return (
    <Box
      sx={{
        position: "absolute",
        top: 0,
        left: 0,
        width: "100%",
        height: "100%",
        overflow: "hidden",
        zIndex: 0,
        background: "linear-gradient(135deg, #1e3c72 0%, #2a5298 100%)",
      }}
    >
      <canvas ref={canvasRef} style={{ display: "block" }} />
    </Box>
  );
};

export default AnimatedBackground;
