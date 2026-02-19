import React, { useState } from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, User, Calendar, MapPin, Edit3 } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface EditProfileScreenProps {
  onBack: () => void;
  onSave: (profile: any) => void;
}

export function EditProfileScreen({ onBack, onSave }: EditProfileScreenProps) {
  const [name, setName] = useState('John Doe');
  const [age, setAge] = useState('28');
  const [location, setLocation] = useState('San Francisco, CA');
  const [bio, setBio] = useState('Entrepreneur focused on sustainable technology');

  const handleSave = () => {
    onSave({ name, age, location, bio });
  };

  const canSave = name.trim() && age.trim();

  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="flex-shrink-0 px-6 pt-14 pb-6 border-b border-[#2A2A2E]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <h1 className="text-white text-2xl">Edit Profile</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-32 space-y-6">
        {/* Avatar */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="flex flex-col items-center"
        >
          <div className="relative mb-4">
            <div className="w-24 h-24 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-xl shadow-[#7B61FF]/30">
              <span className="text-white text-3xl font-bold">JD</span>
            </div>
            <motion.button
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              className="absolute bottom-0 right-0 w-8 h-8 rounded-full bg-[#7B61FF] border-2 border-[#121212] flex items-center justify-center"
            >
              <Edit3 className="w-4 h-4 text-white" />
            </motion.button>
          </div>
          <p className="text-[#A1A1AA] text-sm">Tap to change photo</p>
        </motion.div>

        {/* Name */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <User className="w-4 h-4" />
            Name
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Your name"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Age */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <Calendar className="w-4 h-4" />
            Age
          </label>
          <input
            type="number"
            value={age}
            onChange={(e) => setAge(e.target.value)}
            placeholder="Your age"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Location */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            <MapPin className="w-4 h-4" />
            Location (optional)
          </label>
          <input
            type="text"
            value={location}
            onChange={(e) => setLocation(e.target.value)}
            placeholder="City, Country"
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all"
          />
        </motion.div>

        {/* Bio */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5, duration: 0.4 }}
        >
          <label className="flex items-center gap-2 text-[#A1A1AA] text-sm mb-2">
            Bio (optional)
          </label>
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value)}
            placeholder="A few words about yourself..."
            rows={3}
            className="w-full bg-[#1C1C1E] border border-[#2A2A2E] rounded-[16px] px-4 py-3 text-white placeholder-[#A1A1AA] focus:outline-none focus:border-[#7B61FF]/50 transition-all resize-none"
          />
        </motion.div>

        {/* Info */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.6, duration: 0.4 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E]"
        >
          <p className="text-[#A1A1AA] text-sm leading-relaxed">
            Your profile information helps us personalize your experience and create accurate comparisons with your idols.
          </p>
        </motion.div>
      </div>

      {/* Save Button */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.7, duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-8 bg-gradient-to-t from-[#121212] via-[#121212] to-transparent border-t border-[#2A2A2E]"
      >
        <PrimaryButton onClick={handleSave} disabled={!canSave}>
          Save changes
        </PrimaryButton>
      </motion.div>
    </div>
  );
}
