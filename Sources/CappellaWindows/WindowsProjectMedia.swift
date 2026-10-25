import Foundation
import CappellaCore
import WinUI
import WindowsFoundation

extension WindowsEditor {
    func unloadProjectMedia() {
        media.unload()
        // Clearing Source alone can leave the final video frame on the surface.
        try? videoView.setMediaPlayer(nil)
        try? projectionVideo?.setMediaPlayer(nil)
        videoView.visibility = .collapsed
        previewImage?.visibility = .visible
        playbackFrame = nil; logicalFrame = nil; timelineClock.reset()
        bandMotion.stop()
    }
    func loadProjectMedia() throws {
        try? videoView.setMediaPlayer(nil)
        try? projectionVideo?.setMediaPlayer(nil)
        do {
            try media.open(videoPath: self.document.project.videoPath, audioPath: self.document.project.audioPath)
            if media.hasVideo {
                try videoView.setMediaPlayer(media.video)
                try projectionVideo?.setMediaPlayer(media.video)
            }
        } catch {
            unloadProjectMedia(); refresh(); throw error
        }
        media.seek(Double(self.document.frame - self.document.project.mediaStartFrame) / Double(fps))
        refresh()
    }
    func newProject() async {
        guard await mayReplace(), !isClosed else { return }
        unloadProjectMedia()
        self.document.replace(with: Project(), url: nil)
        refresh()
    }
}