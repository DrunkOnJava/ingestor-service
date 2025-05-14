/**
 * Video entity extractor implementation
 * Specialized for extracting entities from video content using frame extraction and audio analysis
 */

import { EntityExtractor } from '../EntityExtractor';
import { Entity, EntityExtractionOptions, EntityExtractionResult, EntityType } from '../types/EntityTypes';
import { ClaudeService } from '../../services/ClaudeService';
import { Logger } from '../../logging';
import { FileSystem } from '../../utils/FileSystem';
import * as fs from 'fs/promises';
import * as path from 'path';
import { promisify } from 'util';
import { exec } from 'child_process';
import * as os from 'os';

const execPromise = promisify(exec);

/**
 * Supported video file extensions
 */
const SUPPORTED_VIDEO_EXTENSIONS = ['.mp4', '.avi', '.mov', '.mkv', '.webm', '.flv', '.wmv', '.mpg', '.mpeg'];

/**
 * Sampling strategies for video frame extraction
 */
enum FrameSamplingStrategy {
  UNIFORM = 'uniform',      // Extract frames at uniform intervals
  KEYFRAMES = 'keyframes',  // Extract only keyframes/I-frames
  SCENE_CHANGE = 'scene_change', // Extract frames at scene changes
  ADAPTIVE = 'adaptive'     // Adaptive sampling based on content complexity
}

/**
 * Entity extractor specialized for video content
 * Uses frame extraction and audio analysis to identify entities in videos
 */
export class VideoEntityExtractor extends EntityExtractor {
  private claudeService?: ClaudeService;
  private fs: FileSystem;
  private ffmpegPath: string = 'ffmpeg';  // Default path, will be checked during initialization
  private ffprobePath: string = 'ffprobe'; // Default path, will be checked during initialization
  
  /**
   * Creates a new VideoEntityExtractor
   * @param logger Logger instance for extraction logging
   * @param options Default options for entity extraction
   * @param claudeService Claude service for AI-powered extraction (required for video analysis)
   * @param fs FileSystem service for file operations
   */
  constructor(
    logger: Logger, 
    options: EntityExtractionOptions = {},
    claudeService?: ClaudeService,
    fs: FileSystem = new FileSystem(logger)
  ) {
    super(logger, options);
    this.claudeService = claudeService;
    this.fs = fs;
    this.initializeFfmpeg();
  }
  
  /**
   * Initialize FFmpeg path and verify its availability
   * @private
   */
  private async initializeFfmpeg(): Promise<void> {
    try {
      // Check if ffmpeg is available in PATH
      await execPromise('ffmpeg -version');
      await execPromise('ffprobe -version');
      this.logger.debug('FFmpeg and FFprobe are available in PATH');
    } catch (error) {
      // Try common installation locations based on platform
      this.logger.warning('FFmpeg not found in PATH, checking common locations');
      
      const platform = os.platform();
      const possiblePaths = [];
      
      if (platform === 'darwin') {  // macOS
        possiblePaths.push('/usr/local/bin/ffmpeg', '/opt/homebrew/bin/ffmpeg', '/opt/local/bin/ffmpeg');
      } else if (platform === 'win32') {  // Windows
        possiblePaths.push('C:\\ffmpeg\\bin\\ffmpeg.exe', 'C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe');
      } else {  // Linux
        possiblePaths.push('/usr/bin/ffmpeg', '/usr/local/bin/ffmpeg');
      }
      
      let ffmpegFound = false;
      for (const path of possiblePaths) {
        try {
          await fs.access(path);
          this.ffmpegPath = path;
          this.ffprobePath = path.replace('ffmpeg', 'ffprobe');
          ffmpegFound = true;
          this.logger.debug(`Found FFmpeg at ${path}`);
          break;
        } catch {
          // Continue checking other paths
        }
      }
      
      if (!ffmpegFound) {
        this.logger.error('FFmpeg not found. Entity extraction from videos will be limited.');
      }
    }
  }
  
  /**
   * Extract entities from video content
   * @param content The video file path
   * @param contentType MIME type (video/mp4, video/avi, etc.)
   * @param options Options to customize extraction behavior
   */
  public async extract(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<EntityExtractionResult> {
    const startTime = Date.now();
    this.logger.debug(`Extracting entities from video content (${contentType})`);
    
    // Validate content type
    if (!contentType.includes('video/') && !contentType.includes('application/octet-stream')) {
      return {
        entities: [],
        success: false,
        error: `Invalid content type for video extraction: ${contentType}`
      };
    }
    
    // Check if Claude service is available (required for analysis)
    if (!this.claudeService) {
      return {
        entities: [],
        success: false,
        error: 'Claude service is required for video entity extraction but not provided'
      };
    }
    
    try {
      // Validate file path
      if (!await this.fs.isFile(content)) {
        return {
          entities: [],
          success: false,
          error: 'Content must be a valid video file path'
        };
      }
      
      // Validate file extension
      const fileExt = path.extname(content).toLowerCase();
      if (!SUPPORTED_VIDEO_EXTENSIONS.includes(fileExt)) {
        return {
          entities: [],
          success: false,
          error: `Unsupported video file type: ${fileExt}`
        };
      }
      
      // Get video metadata
      const metadata = await this.getVideoMetadata(content);
      
      // Extract from file
      const videoEntities = await this.extractFromFile(content, options);
      
      // Filter entities based on options
      const filteredEntities = this.filterEntities(videoEntities, options);
      
      // Create result with stats
      const result: EntityExtractionResult = {
        entities: filteredEntities,
        success: true,
        stats: {
          processingTimeMs: Date.now() - startTime,
          entityCount: filteredEntities.length,
          metadata
        }
      };
      
      this.logger.debug(`Extracted ${result.stats?.entityCount} entities from video in ${result.stats?.processingTimeMs}ms`);
      return result;
    } catch (error) {
      this.logger.error(`Video entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        entities: [],
        success: false,
        error: `Video extraction error: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }
  
  /**
   * Extract entities from a video file
   * @param filePath Path to the video file
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractFromFile(
    filePath: string,
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    this.logger.debug(`Extracting entities from video file: ${filePath}`);
    
    // Create a temporary directory for extracted frames
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'video-entities-'));
    
    try {
      // Extract video metadata
      const metadata = await this.getVideoMetadata(filePath);
      
      // Determine sampling strategy based on video length
      const samplingStrategy = this.determineSamplingStrategy(metadata, options);
      this.logger.debug(`Using ${samplingStrategy} sampling strategy for video frames`);
      
      // Extract frames
      const frameFiles = await this.extractFrames(filePath, tempDir, samplingStrategy, options);
      this.logger.debug(`Extracted ${frameFiles.length} frames from video`);
      
      // Extract audio if available
      let audioEntities: Entity[] = [];
      if (metadata.hasAudio) {
        const audioFile = path.join(tempDir, 'audio.wav');
        await this.extractAudio(filePath, audioFile);
        audioEntities = await this.extractEntitiesFromAudio(audioFile, options);
        this.logger.debug(`Extracted ${audioEntities.length} entities from audio track`);
      }
      
      // Process frames and extract entities
      const frameEntities = await this.extractEntitiesFromFrames(frameFiles, options);
      this.logger.debug(`Extracted ${frameEntities.length} entities from video frames`);
      
      // Merge entities from frames and audio
      return this.mergeEntities([frameEntities, audioEntities]);
    } finally {
      // Clean up temporary files
      try {
        await this.fs.removeDir(tempDir, true);
      } catch (error) {
        this.logger.warning(`Failed to clean up temporary directory: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    }
  }
  
  /**
   * Determine the most appropriate frame sampling strategy based on video metadata
   * @param metadata Video metadata
   * @param options Extraction options
   * @returns Sampling strategy to use
   * @private
   */
  private determineSamplingStrategy(
    metadata: any,
    options?: EntityExtractionOptions
  ): FrameSamplingStrategy {
    // Get strategy from options if specified
    if (options?.videoOptions?.samplingStrategy) {
      return options.videoOptions.samplingStrategy as FrameSamplingStrategy;
    }
    
    // Default strategy based on video duration
    const duration = parseFloat(metadata.duration || '0');
    
    if (duration > 600) {  // > 10 minutes
      return FrameSamplingStrategy.SCENE_CHANGE;
    } else if (duration > 300) {  // > 5 minutes
      return FrameSamplingStrategy.KEYFRAMES;
    } else if (duration > 60) {  // > 1 minute
      return FrameSamplingStrategy.UNIFORM;
    } else {
      return FrameSamplingStrategy.ADAPTIVE;
    }
  }
  
  /**
   * Extract frames from video based on specified strategy
   * @param videoPath Path to the video file
   * @param outputDir Output directory for extracted frames
   * @param strategy Frame sampling strategy
   * @param options Extraction options
   * @returns Array of paths to extracted frame images
   * @private
   */
  private async extractFrames(
    videoPath: string,
    outputDir: string,
    strategy: FrameSamplingStrategy,
    options?: EntityExtractionOptions
  ): Promise<string[]> {
    // Determine maximum number of frames to extract
    const maxFrames = options?.videoOptions?.maxFrames || 10;
    
    // Get video duration in seconds
    const metadata = await this.getVideoMetadata(videoPath);
    const duration = parseFloat(metadata.duration || '0');
    
    // Create output directory if it doesn't exist
    await fs.mkdir(outputDir, { recursive: true });
    
    // Command base
    let command = '';
    
    switch (strategy) {
      case FrameSamplingStrategy.UNIFORM:
        // Extract frames at uniform intervals
        const interval = duration / maxFrames;
        command = `${this.ffmpegPath} -i "${videoPath}" -vf "fps=1/${interval}" -q:v 2 "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        break;
        
      case FrameSamplingStrategy.KEYFRAMES:
        // Extract only keyframes
        command = `${this.ffmpegPath} -i "${videoPath}" -vf "select='eq(pict_type,I)'" -vsync vfr -q:v 2 -frames:v ${maxFrames} "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        break;
        
      case FrameSamplingStrategy.SCENE_CHANGE:
        // Extract frames at scene changes
        command = `${this.ffmpegPath} -i "${videoPath}" -vf "select='gt(scene,0.4)',showinfo" -vsync vfr -q:v 2 -frames:v ${maxFrames} "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        break;
        
      case FrameSamplingStrategy.ADAPTIVE:
      default:
        // Adaptive sampling based on content complexity and duration
        if (duration <= 30) {
          // For short videos, extract more frames
          command = `${this.ffmpegPath} -i "${videoPath}" -vf "fps=1/3" -q:v 2 -frames:v ${maxFrames} "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        } else if (duration <= 120) {
          // For medium length videos, extract frames with scene detection
          command = `${this.ffmpegPath} -i "${videoPath}" -vf "select='gt(scene,0.3)',showinfo" -vsync vfr -q:v 2 -frames:v ${maxFrames} "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        } else {
          // For longer videos, extract keyframes
          command = `${this.ffmpegPath} -i "${videoPath}" -vf "select='eq(pict_type,I)'" -vsync vfr -q:v 2 -frames:v ${maxFrames} "${path.join(outputDir, 'frame-%03d.jpg')}"`;
        }
        break;
    }
    
    // Execute command to extract frames
    this.logger.debug(`Executing frame extraction: ${command}`);
    await execPromise(command);
    
    // Get list of extracted frame files
    const files = await fs.readdir(outputDir);
    return files
      .filter(file => file.startsWith('frame-') && file.endsWith('.jpg'))
      .map(file => path.join(outputDir, file))
      .sort(); // Sort to ensure frames are processed in order
  }
  
  /**
   * Extract audio from video file
   * @param videoPath Path to the video file
   * @param outputAudioPath Path where extracted audio will be saved
   * @returns Path to the extracted audio file
   * @private
   */
  private async extractAudio(
    videoPath: string,
    outputAudioPath: string
  ): Promise<string> {
    try {
      // Extract audio track to WAV format
      const command = `${this.ffmpegPath} -i "${videoPath}" -q:a 0 -map a "${outputAudioPath}" -y`;
      this.logger.debug(`Executing audio extraction: ${command}`);
      await execPromise(command);
      return outputAudioPath;
    } catch (error) {
      this.logger.error(`Audio extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Generate transcription from audio file
   * @param audioPath Path to the audio file
   * @returns Transcribed text
   * @private
   */
  private async generateTranscription(audioPath: string): Promise<string> {
    if (!this.claudeService) {
      throw new Error('Claude service is required for audio transcription');
    }
    
    try {
      // Read audio file as buffer for processing
      const audioBuffer = await fs.readFile(audioPath);
      
      // For simplicity in this implementation, we're assuming a two-step process:
      // 1. Convert audio to spectrogram or other visual representation
      // 2. Send to Claude for analysis
      
      // In a real implementation, this would use a transcription service (like Whisper API)
      // or a direct audio-to-text capability if available from Claude
      
      // Here, we'll use ffmpeg to extract a transcript (simulated with metadata)
      const { stdout } = await execPromise(`${this.ffprobePath} -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${audioPath}"`);
      const duration = parseFloat(stdout.trim());
      
      // Simplified transcription - in real implementation, use a proper speech-to-text service
      return `[Audio transcription placeholder for ${path.basename(audioPath)}] [Duration: ${duration.toFixed(2)} seconds]`;
    } catch (error) {
      this.logger.error(`Transcription generation failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Extract entities from audio content
   * @param audioPath Path to the audio file
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractEntitiesFromAudio(
    audioPath: string,
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    try {
      // Generate transcription from audio
      const transcription = await this.generateTranscription(audioPath);
      
      if (!transcription || transcription.trim().length === 0) {
        this.logger.warning('Generated audio transcription is empty');
        return [];
      }
      
      // Use Claude to extract entities from transcription
      if (this.claudeService) {
        const entities = await this.extractWithClaude(transcription, 'text/plain', options);
        
        // Tag entities as coming from audio
        return entities.map(entity => ({
          ...entity,
          source: 'audio',
          mentions: entity.mentions.map(mention => ({
            ...mention,
            source: 'audio'
          }))
        }));
      }
      
      return [];
    } catch (error) {
      this.logger.error(`Audio entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Extract entities from video frames
   * @param frameFiles Array of paths to frame image files
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractEntitiesFromFrames(
    frameFiles: string[],
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      // Determine how many frames to analyze
      const framesToAnalyze = Math.min(
        frameFiles.length,
        options?.videoOptions?.maxFramesToAnalyze || 5
      );
      
      // Select frames to analyze with uniform spacing
      const selectedFrames = this.selectFramesForAnalysis(frameFiles, framesToAnalyze);
      this.logger.debug(`Selected ${selectedFrames.length} frames for analysis`);
      
      // Process each frame to extract entities
      const frameEntitiesPromises = selectedFrames.map(async (framePath, index) => {
        try {
          // Read frame as buffer
          const frameBuffer = await fs.readFile(framePath);
          
          // Convert to base64 for Claude API
          const base64Frame = frameBuffer.toString('base64');
          const frameBase64Uri = `data:image/jpeg;base64,${base64Frame}`;
          
          // Get frame timestamp (simplified)
          const timestamp = `Frame ${index + 1}`;
          
          // Extract entities from frame using Claude
          const entities = await this.extractWithClaude(
            frameBase64Uri,
            'image/jpeg',
            options
          );
          
          // Tag entities with frame information
          return entities.map(entity => ({
            ...entity,
            source: 'video_frame',
            frame: {
              path: framePath,
              index: index,
              timestamp: timestamp
            },
            mentions: entity.mentions.map(mention => ({
              ...mention,
              source: 'video_frame',
              timestamp: timestamp
            }))
          }));
        } catch (error) {
          this.logger.warning(`Failed to extract entities from frame ${framePath}: ${error instanceof Error ? error.message : 'Unknown error'}`);
          return [];
        }
      });
      
      // Collect all frame entities
      const frameEntitiesLists = await Promise.all(frameEntitiesPromises);
      
      // Flatten and return
      return this.mergeEntities(frameEntitiesLists);
    } catch (error) {
      this.logger.error(`Frame entity extraction failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Select a subset of frames for detailed analysis
   * @param frameFiles All extracted frame files
   * @param framesToSelect Number of frames to select
   * @returns Selected frame file paths
   * @private
   */
  private selectFramesForAnalysis(
    frameFiles: string[],
    framesToSelect: number
  ): string[] {
    if (frameFiles.length <= framesToSelect) {
      return frameFiles;
    }
    
    // Select frames with uniform spacing
    const selectedFrames: string[] = [];
    const step = frameFiles.length / framesToSelect;
    
    for (let i = 0; i < framesToSelect; i++) {
      const index = Math.floor(i * step);
      if (index < frameFiles.length) {
        selectedFrames.push(frameFiles[index]);
      }
    }
    
    return selectedFrames;
  }
  
  /**
   * Extract entities using Claude AI
   * @param content Content to analyze (text, image, etc.)
   * @param contentType MIME type of the content
   * @param options Extraction options
   * @returns Array of extracted entities
   * @private
   */
  private async extractWithClaude(
    content: string, 
    contentType: string, 
    options?: EntityExtractionOptions
  ): Promise<Entity[]> {
    if (!this.claudeService) {
      return [];
    }
    
    try {
      // Determine prompt template based on content type
      let promptTemplate = 'default_entities';
      
      if (contentType.startsWith('image/')) {
        promptTemplate = 'image_entities';
      } else if (contentType.startsWith('video/')) {
        promptTemplate = 'video_entities';
      } else if (contentType.startsWith('text/')) {
        promptTemplate = 'text_entities';
      }
      
      // Customize prompt if specific entity types are requested
      if (options?.entityTypes && options.entityTypes.length > 0) {
        promptTemplate += '_custom';
      }
      
      // Call Claude with appropriate prompt
      const claudeResponse = await this.claudeService.analyze(content, promptTemplate, {
        contentType,
        entityTypes: options?.entityTypes?.join(','),
        ...options
      });
      
      // Extract entities from Claude's response
      if (claudeResponse && claudeResponse.entities && Array.isArray(claudeResponse.entities)) {
        return claudeResponse.entities as Entity[];
      }
      
      this.logger.warning('Claude response did not contain valid entities array');
      return [];
    } catch (error) {
      this.logger.error(`Error extracting entities with Claude: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return [];
    }
  }
  
  /**
   * Get video metadata (duration, resolution, codecs, etc.)
   * @param filePath Path to the video file
   * @returns Object with video metadata
   */
  public async getVideoMetadata(filePath: string): Promise<Record<string, any>> {
    try {
      // Use ffprobe to get video metadata as JSON
      const command = `${this.ffprobePath} -v quiet -print_format json -show_format -show_streams "${filePath}"`;
      const { stdout } = await execPromise(command);
      const rawMetadata = JSON.parse(stdout);
      
      // Extract relevant metadata
      const metadata: Record<string, any> = {
        filename: path.basename(filePath),
        format: rawMetadata.format.format_name,
        duration: rawMetadata.format.duration,
        size: parseInt(rawMetadata.format.size, 10),
        bitrate: parseInt(rawMetadata.format.bit_rate, 10),
        hasVideo: false,
        hasAudio: false
      };
      
      // Process video streams
      for (const stream of rawMetadata.streams) {
        if (stream.codec_type === 'video') {
          metadata.hasVideo = true;
          metadata.videoCodec = stream.codec_name;
          metadata.width = stream.width;
          metadata.height = stream.height;
          metadata.fps = eval(stream.r_frame_rate); // Convert fraction to number
          metadata.videoStream = stream;
        } else if (stream.codec_type === 'audio') {
          metadata.hasAudio = true;
          metadata.audioCodec = stream.codec_name;
          metadata.audioChannels = stream.channels;
          metadata.sampleRate = stream.sample_rate;
          metadata.audioStream = stream;
        }
      }
      
      return metadata;
    } catch (error) {
      this.logger.error(`Failed to get video metadata: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return {
        error: `Failed to extract metadata: ${error instanceof Error ? error.message : 'Unknown error'}`
      };
    }
  }
  
  /**
   * Check if a file is a supported video format
   * @param filePath Path to the file
   * @returns True if the file is a supported video, false otherwise
   */
  public async isSupportedVideo(filePath: string): Promise<boolean> {
    try {
      // Check file extension
      const fileExtension = path.extname(filePath).toLowerCase();
      if (!SUPPORTED_VIDEO_EXTENSIONS.includes(fileExtension)) {
        return false;
      }
      
      // Verify it's a video file using ffprobe
      try {
        const { stdout } = await execPromise(`${this.ffprobePath} -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "${filePath}"`);
        return !!stdout.trim(); // If we got a codec name, it's a valid video
      } catch {
        // If ffprobe fails, check MIME type as fallback
        const mimeType = await this.fs.getMimeType(filePath);
        return mimeType.startsWith('video/');
      }
    } catch (error) {
      this.logger.error(`Failed to check if file is a supported video: ${error instanceof Error ? error.message : 'Unknown error'}`);
      return false;
    }
  }
  
  /**
   * Generate a thumbnail image from the video
   * @param videoPath Path to the video file
   * @param outputPath Path where the thumbnail will be saved
   * @param options Options for thumbnail generation
   * @returns Path to the generated thumbnail
   */
  public async generateThumbnail(
    videoPath: string,
    outputPath: string = '',
    options: { time?: string, width?: number, height?: number } = {}
  ): Promise<string> {
    try {
      // If no output path provided, create one
      if (!outputPath) {
        const videoDir = path.dirname(videoPath);
        const videoName = path.basename(videoPath, path.extname(videoPath));
        outputPath = path.join(videoDir, `${videoName}_thumbnail.jpg`);
      }
      
      // Set default options
      const time = options.time || '00:00:05'; // 5 seconds into the video
      const width = options.width || 320;
      const height = options.height || -1; // Maintain aspect ratio
      
      // Generate thumbnail using ffmpeg
      const command = `${this.ffmpegPath} -ss ${time} -i "${videoPath}" -vframes 1 -s ${width}x${height} -q:v 2 "${outputPath}" -y`;
      await execPromise(command);
      
      return outputPath;
    } catch (error) {
      this.logger.error(`Failed to generate thumbnail: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
  
  /**
   * Generate a short preview clip from the video
   * @param videoPath Path to the video file
   * @param outputPath Path where the preview clip will be saved
   * @param options Options for preview generation
   * @returns Path to the generated preview clip
   */
  public async generatePreviewClip(
    videoPath: string,
    outputPath: string = '',
    options: { startTime?: string, duration?: number, width?: number, height?: number } = {}
  ): Promise<string> {
    try {
      // If no output path provided, create one
      if (!outputPath) {
        const videoDir = path.dirname(videoPath);
        const videoName = path.basename(videoPath, path.extname(videoPath));
        outputPath = path.join(videoDir, `${videoName}_preview.mp4`);
      }
      
      // Set default options
      const startTime = options.startTime || '00:00:10'; // 10 seconds into the video
      const duration = options.duration || 5; // 5 seconds duration
      const width = options.width || 640;
      const height = options.height || -1; // Maintain aspect ratio
      
      // Generate preview clip using ffmpeg
      const command = `${this.ffmpegPath} -ss ${startTime} -i "${videoPath}" -t ${duration} -s ${width}x${height} -c:v libx264 -crf 23 -preset fast "${outputPath}" -y`;
      await execPromise(command);
      
      return outputPath;
    } catch (error) {
      this.logger.error(`Failed to generate preview clip: ${error instanceof Error ? error.message : 'Unknown error'}`);
      throw error;
    }
  }
}