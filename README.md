# hotswap
Basic AI framework for Swapping Video Characters
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/6b0ae93a-8d24-4b06-b543-317819f0abd4" />

At present, this is no more than a gist intended to answer the question, "How do I cartoonify an interview or discussion so the cartoon/animation/avatar retains actions and expressions of the original person, but the actual person is no longer identifiable (don't want masked or pixelated)."

Here is what I would do using the tools I'm familiar with at this moment:

Use something like [PySceneDetect](https://github.com/breakthrough/pyscenedetect) to generate a list of camera cuts and feed that into ffmpeg to slice the interview into clips + extract the first frame of each.  That would look something like this:<img width="1907" height="882" alt="1" src="https://github.com/user-attachments/assets/4640f14b-dab5-439d-adf0-ed0af2fd5d49" />

Then, you'd run each start frame through a diffuser to generate your cartoon.  There are a million possibilities here, but using Klein 4b in Comfy looks like this:<img width="1920" height="1080" alt="2" src="https://github.com/user-attachments/assets/73003870-884b-4609-963a-5b66a94aa890" />

Finally, for each pair of clips and stylized images you'd run them through a video model.  Again, many possibilities... but KJ's WanAnimate ComfyUI setup looks like this <img width="1920" height="1080" alt="3" src="https://github.com/user-attachments/assets/e86a50fd-0d81-409c-b9ae-6c69355a43b7" />

End result as a mp4 file: 
https://github.com/user-attachments/assets/31daa377-b057-4d08-919a-cbc96f3a9d3f

Because I automated most of this and used a single reference image (of a Harry Potter cartoon dude with a Butterbeer) for all clips without review or editing, there are some inconsistencies between scenes.  In the context of creating anonymity, I think it's actually kind of cool.  But a more refined workflow would either hand-craft the reference images or at least use an automated edit process to transform the starting one for each clip's first frame instead of total replacement.  Modern edit diffusers can achieve this nicely.
