import React from "react";
import { Composition } from "remotion";
import { DURATION_S, FPS, Film } from "./Film";

export const Root: React.FC = () => (
  <>
    <Composition id="Wide" component={Film} durationInFrames={Math.round(DURATION_S * FPS)} fps={FPS} width={1920} height={1080} defaultProps={{ tall: false }} />
    <Composition id="Tall" component={Film} durationInFrames={Math.round(DURATION_S * FPS)} fps={FPS} width={1080} height={1350} defaultProps={{ tall: true }} />
  </>
);
