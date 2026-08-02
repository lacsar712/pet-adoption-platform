const path = require("path");
const fs = require("fs");
const crypto = require("crypto");
const streamifier = require("streamifier");
const cloudinary = require("../config/cloudinary");

const uploadsDir = process.env.UPLOAD_DIR || path.join(__dirname, "../../uploads");

const hasCloudinary =
  process.env.CLOUDINARY_CLOUD_NAME &&
  process.env.CLOUDINARY_API_KEY &&
  process.env.CLOUDINARY_API_SECRET;

const uploadToCloudinary = (buffer) => {
  return new Promise((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: "pet-adoption-platform"
      },
      (error, result) => {
        if (error) {
          reject(error);
        } else {
          resolve(result);
        }
      }
    );

    streamifier.createReadStream(buffer).pipe(stream);
  });
};

const uploadLocally = (buffer, originalname = "image.jpg") => {
  fs.mkdirSync(uploadsDir, { recursive: true });

  const ext = path.extname(originalname) || ".jpg";
  const filename = `${Date.now()}-${crypto.randomBytes(8).toString("hex")}${ext}`;
  fs.writeFileSync(path.join(uploadsDir, filename), buffer);

  return { secure_url: `/uploads/${filename}` };
};

const uploadImagem = (buffer, originalname) => {
  if (hasCloudinary) {
    return uploadToCloudinary(buffer);
  }

  return Promise.resolve(uploadLocally(buffer, originalname));
};

module.exports = {
  uploadImagem,
  uploadsDir
};
