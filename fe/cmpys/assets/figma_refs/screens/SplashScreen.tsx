import React from 'react';
import { motion } from 'motion/react';
import { PrimaryButton } from '../PrimaryButton';
import { Sparkles } from 'lucide-react';

interface SplashScreenProps {
  onStart: () => void;
}

export function SplashScreen({ onStart }: SplashScreenProps) {
  return (
    <div className="h-screen bg-[#121212] flex flex-col items-center justify-center px-6 relative overflow-hidden">
      {/* Optional: Video Background */}
      {/* Uncomment and add your video file to use video background */}
      {/* <video 
        className="absolute inset-0 w-full h-full object-cover opacity-20"
        autoPlay 
        loop 
        muted 
        playsInline
      >
        <source src="/path-to-your-video.mp4" type="video/mp4" />
      </video> */}

      {/* Animated gradient background */}
      <motion.div
        className="absolute inset-0 bg-gradient-to-br from-[#7B61FF]/10 via-transparent to-[#A78BFA]/10"
        animate={{
          opacity: [0.3, 0.6, 0.3],
        }}
        transition={{
          type: "tween",
          duration: 4,
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />

      {/* Floating particles */}
      {[...Array(6)].map((_, i) => (
        <motion.div
          key={i}
          className="absolute w-2 h-2 rounded-full bg-[#7B61FF]/30"
          initial={{
            x: Math.random() * 400 - 200,
            y: Math.random() * 800,
          }}
          animate={{
            y: -100,
            opacity: [0, 1, 0],
          }}
          transition={{
            type: "tween",
            duration: 3 + Math.random() * 2,
            repeat: Infinity,
            delay: Math.random() * 2,
            ease: "linear",
          }}
          style={{
            left: `${20 + Math.random() * 60}%`,
          }}
        />
      ))}

      <div className="flex-1 flex items-center justify-center flex-col relative z-10">
        {/* App Icon with pulsing animation */}
        <motion.div
          initial={{ scale: 0, rotate: -180 }}
          animate={{ scale: 1, rotate: 0 }}
          transition={{
            type: "spring",
            stiffness: 100,
            damping: 15,
            duration: 0.8,
          }}
          className="w-20 h-20 rounded-[24px] bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center mb-8 relative"
        >
          <motion.div
            className="absolute inset-0 rounded-[24px] bg-gradient-to-br from-[#7B61FF] to-[#A78BFA]"
            animate={{
              scale: [1, 1.2, 1],
              opacity: [0.5, 0, 0.5],
            }}
            transition={{
              type: "tween",
              duration: 2,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          />
          <motion.div
            animate={{
              rotate: [0, 10, -10, 0],
            }}
            transition={{
              type: "tween",
              duration: 3,
              repeat: Infinity,
              ease: "easeInOut",
            }}
          >
            <Sparkles className="w-10 h-10 text-white" />
          </motion.div>
        </motion.div>

        {/* App Title with slide up animation */}
        <motion.h1
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.6 }}
          className="text-white text-4xl mb-3 tracking-tight"
        >
          CMPYS
        </motion.h1>

        {/* Subtitle with fade in */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.5, duration: 0.6 }}
          className="text-[#A1A1AA] text-center"
        >
          Compare Your Success
        </motion.p>
      </div>

      {/* Button with slide up animation */}
      <motion.div
        initial={{ opacity: 0, y: 50 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.7, duration: 0.6 }}
        className="w-full pb-8 relative z-10"
      >
        <PrimaryButton onClick={onStart}>Let's start</PrimaryButton>
      </motion.div>
    </div>
  );
}